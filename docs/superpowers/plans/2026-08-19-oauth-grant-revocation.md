# OAuth Grant Revocation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A "Connected apps" section on `/admin/settings` listing OAuth clients with live MCP access, with per-client revocation.

**Architecture:** Two domain functions on `Newton.OAuth` (an aggregate listing query and a bulk revoke), then a settings-page section that mirrors the passkey list and guards revocation with the existing event-time sudo re-check.

**Tech Stack:** Phoenix 1.8 LiveView, Ecto. No new dependencies.

## Global Constraints

- Spec: `docs/superpowers/specs/2026-08-19-oauth-grant-revocation-design.md`
- "Active grant" = `revoked_at` is nil AND (access token unexpired OR refresh token unexpired); clients with zero active grants never appear
- Revocation is per-client (all active grants at once) and does NOT delete the client registration
- Revoke re-checks sudo freshness at event time via the existing `with_fresh_sudo` (mirror `delete_passkey`)
- Revoking a grantless client is a clean no-op (returns 0, no crash, no error flash)
- Telemetry: reuse the `[:newton, :oauth, :grant]` span via `Newton.Telemetry.span(:oauth, :grant, ...)` with metadata `%{operation: :admin_revoke, result: :ok}` — bounded values only
- No narrating comments; predicate names end in `?`; `mix format` before every commit
- Commit subjects as given; the executing session appends its required trailer block

---

### Task 1: Domain — `list_authorized_clients/0` and `revoke_client_grants/1`

**Files:**
- Modify: `lib/newton/oauth.ex`
- Test: `test/newton/oauth_test.exs`

**Interfaces:**
- Consumes: existing `OAuth.register_client/1`, `issue_code/4`, `exchange_code/4`, `verify_access_token/1`, `refresh/2`, `generate_secret/0`, `hash/1`, the `Grant`/`Client` schemas, and private helpers `now/0` (existing)
- Produces (Task 2 relies on these exactly):
  - `Newton.OAuth.list_authorized_clients() :: [%{client: %Client{}, first_connected_at: DateTime.t(), last_active_at: DateTime.t(), grant_count: pos_integer()}]` — ordered by `last_active_at` desc
  - `Newton.OAuth.revoke_client_grants(%Client{}) :: non_neg_integer()` — count of grants revoked

- [ ] **Step 1: Write the failing tests**

Append to `test/newton/oauth_test.exs`, inside the module (a new describe after the existing ones; the helper goes inside the describe):

```elixir
  describe "authorized clients" do
    defp connected_client(name) do
      {:ok, {client, _secret}} =
        OAuth.register_client(%{
          "client_name" => name,
          "redirect_uris" => ["https://claude.ai/api/mcp/auth_callback"],
          "token_endpoint_auth_method" => "none"
        })

      {client, connect(client)}
    end

    defp connect(client) do
      verifier = OAuth.generate_secret()
      challenge = Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)

      {:ok, code} =
        OAuth.issue_code(
          client,
          "https://claude.ai/api/mcp/auth_callback",
          challenge,
          OAuth.canonical_resource()
        )

      {:ok, tokens} =
        OAuth.exchange_code(client, code, "https://claude.ai/api/mcp/auth_callback", verifier)

      tokens
    end

    test "lists clients with active grants and their aggregates" do
      {client, _tokens1} = connected_client("Claude Code")
      _tokens2 = connect(client)

      assert [entry] = OAuth.list_authorized_clients()
      assert entry.client.id == client.id
      assert entry.grant_count == 2
      assert %DateTime{} = entry.first_connected_at
      assert %DateTime{} = entry.last_active_at
      assert DateTime.compare(entry.first_connected_at, entry.last_active_at) != :gt
    end

    test "orders clients by most recent activity first" do
      {older, _} = connected_client("Older")
      {newer, _} = connected_client("Newer")

      bump_last_activity(newer)

      assert [first, second] = OAuth.list_authorized_clients()
      assert first.client.id == newer.id
      assert second.client.id == older.id
    end

    test "excludes clients whose grants are all revoked" do
      {client, _tokens} = connected_client("Revoked app")
      assert OAuth.revoke_client_grants(client) == 1

      assert OAuth.list_authorized_clients() == []
    end

    test "excludes clients whose grants are fully expired" do
      {client, _tokens} = connected_client("Expired app")
      expire_all_tokens(client)

      assert OAuth.list_authorized_clients() == []
    end

    test "revoke kills every active grant and its tokens" do
      {client, tokens1} = connected_client("Doomed app")
      tokens2 = connect(client)

      :telemetry_test.attach_event_handlers(self(), [[:newton, :oauth, :grant, :stop]])

      assert OAuth.revoke_client_grants(client) == 2

      assert {:error, :invalid_token} = OAuth.verify_access_token(tokens1.access_token)
      assert {:error, :invalid_token} = OAuth.verify_access_token(tokens2.access_token)
      assert {:error, :invalid_grant} = OAuth.refresh(client, tokens1.refresh_token)
      assert {:error, :invalid_grant} = OAuth.refresh(client, tokens2.refresh_token)

      assert_receive {[:newton, :oauth, :grant, :stop], _ref, _m, %{operation: :admin_revoke, result: :ok}}
    end

    test "revoking a grantless client returns 0" do
      {:ok, {client, _}} =
        OAuth.register_client(%{
          "client_name" => "Never connected",
          "redirect_uris" => ["https://claude.ai/api/mcp/auth_callback"],
          "token_endpoint_auth_method" => "none"
        })

      assert OAuth.revoke_client_grants(client) == 0
    end

    defp bump_last_activity(client) do
      import Ecto.Query

      future = DateTime.add(DateTime.utc_now(), 60, :second) |> DateTime.truncate(:second)

      {_, _} =
        Newton.Repo.update_all(
          from(g in Newton.OAuth.Grant, where: g.client_id == ^client.id),
          set: [updated_at: future]
        )
    end

    defp expire_all_tokens(client) do
      import Ecto.Query

      past = DateTime.add(DateTime.utc_now(), -60, :second) |> DateTime.truncate(:second)

      {_, _} =
        Newton.Repo.update_all(
          from(g in Newton.OAuth.Grant, where: g.client_id == ^client.id),
          set: [access_token_expires_at: past, refresh_token_expires_at: past]
        )
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/newton/oauth_test.exs`
Expected: the six new tests FAIL (`list_authorized_clients/0` undefined); all existing tests pass.

- [ ] **Step 3: Implement the two functions**

In `lib/newton/oauth.ex`, after `get_client/1` (add `@type authorized_client` near the module's other types):

```elixir
  @type authorized_client :: %{
          client: %Client{},
          first_connected_at: DateTime.t(),
          last_active_at: DateTime.t(),
          grant_count: pos_integer()
        }

  @doc "Clients holding at least one live grant, most recently active first."
  @spec list_authorized_clients() :: [authorized_client()]
  def list_authorized_clients do
    now = DateTime.utc_now()

    Repo.all(
      from g in Grant,
        join: c in assoc(g, :client),
        where: is_nil(g.revoked_at),
        where: g.access_token_expires_at > ^now or g.refresh_token_expires_at > ^now,
        group_by: c.id,
        order_by: [desc: max(g.updated_at)],
        select: %{
          client: c,
          first_connected_at: min(g.inserted_at),
          last_active_at: max(g.updated_at),
          grant_count: count(g.id)
        }
    )
  end

  @doc "Revokes every unrevoked grant for the client; the registration survives."
  @spec revoke_client_grants(%Client{}) :: non_neg_integer()
  def revoke_client_grants(%Client{} = client) do
    Newton.Telemetry.span(:oauth, :grant, %{operation: :admin_revoke}, fn ->
      {count, _} =
        Repo.update_all(
          from(g in Grant, where: g.client_id == ^client.id and is_nil(g.revoked_at)),
          set: [revoked_at: now()]
        )

      {count, %{operation: :admin_revoke, result: :ok}}
    end)
  end
```

Note: the revoke `where` is deliberately broader than the listing's
active-token definition — it also clears code-phase and expired grants, so
nothing unrevoked survives for that client.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/newton/oauth_test.exs`
Expected: all PASS.

- [ ] **Step 5: Format and commit**

```bash
mix format
git add lib/newton/oauth.ex test/newton/oauth_test.exs
git commit -m "Add authorized-client listing and bulk grant revocation"
```

---

### Task 2: Settings UI — the Connected apps section

**Files:**
- Modify: `lib/newton_web/live/admin/settings_live.ex`
- Test: `test/newton_web/live/admin/settings_live_test.exs`

**Interfaces:**
- Consumes: Task 1's `OAuth.list_authorized_clients/0` and `OAuth.revoke_client_grants/1` (exact shapes in Task 1's Produces block); the page's existing `with_fresh_sudo/2` and `format_day/1` helpers
- Produces: nothing later tasks rely on

- [ ] **Step 1: Write the failing tests**

Append inside `NewtonWeb.Admin.SettingsLiveTest` (before the final `end`). The helper mirrors the OAuth test flow; keep it inside this module:

```elixir
  defp connected_oauth_client(name) do
    alias Newton.OAuth

    {:ok, {client, _secret}} =
      OAuth.register_client(%{
        "client_name" => name,
        "redirect_uris" => ["https://claude.ai/api/mcp/auth_callback"],
        "token_endpoint_auth_method" => "none"
      })

    verifier = OAuth.generate_secret()
    challenge = Base.url_encode64(:crypto.hash(:sha256, verifier), padding: false)

    {:ok, code} =
      OAuth.issue_code(
        client,
        "https://claude.ai/api/mcp/auth_callback",
        challenge,
        OAuth.canonical_resource()
      )

    {:ok, tokens} =
      OAuth.exchange_code(client, code, "https://claude.ai/api/mcp/auth_callback", verifier)

    {client, tokens}
  end

  test "lists connected apps", %{conn: conn} do
    {client, _tokens} = connected_oauth_client("Claude Code (newton)")

    {:ok, view, _html} = live(conn, ~p"/admin/settings")

    assert has_element?(view, "#connected-app-#{client.id}", "Claude Code (newton)")
  end

  test "shows the empty state when nothing is connected", %{conn: conn} do
    {:ok, _view, html} = live(conn, ~p"/admin/settings")

    assert html =~ "No apps have access."
  end

  test "revoking a client removes it and kills its tokens", %{conn: conn} do
    {client, tokens} = connected_oauth_client("Doomed app")
    assert {:ok, _} = Newton.OAuth.verify_access_token(tokens.access_token)

    {:ok, view, _html} = live(conn, ~p"/admin/settings")

    view
    |> element("#connected-app-#{client.id} button", "Revoke")
    |> render_click()

    refute has_element?(view, "#connected-app-#{client.id}")
    assert has_element?(view, "#connected-apps-empty")
    assert {:error, :invalid_token} = Newton.OAuth.verify_access_token(tokens.access_token)
  end

  test "a stale sudo window blocks revoking a client", %{conn: conn} do
    {client, tokens} = connected_oauth_client("Protected app")

    {:ok, view, _} = live(conn, ~p"/admin/settings")
    expire_sudo_window(view)

    render_click(view, "revoke_client", %{"id" => to_string(client.id)})

    assert_redirect(view, ~p"/login/confirm-access")
    assert {:ok, _} = Newton.OAuth.verify_access_token(tokens.access_token)
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/newton_web/live/admin/settings_live_test.exs`
Expected: the four new tests FAIL (no section/element/event); existing tests pass.

- [ ] **Step 3: Wire the LiveView**

In `lib/newton_web/live/admin/settings_live.ex`:

Add the alias beside the existing ones:

```elixir
  alias Newton.OAuth
```

In `mount/3`, add to the assign chain:

```elixir
     |> assign(:authorized_clients, OAuth.list_authorized_clients())
```

Add the event handler after `handle_event("delete_passkey", ...)`:

```elixir
  def handle_event("revoke_client", %{"id" => id}, socket) do
    with_fresh_sudo(socket, fn socket ->
      entry =
        Enum.find(socket.assigns.authorized_clients, &(&1.client.id == String.to_integer(id)))

      socket =
        if entry && OAuth.revoke_client_grants(entry.client) > 0,
          do: put_flash(socket, :info, "#{entry.client.client_name} revoked."),
          else: socket

      assign(socket, :authorized_clients, OAuth.list_authorized_clients())
    end)
  end
```

- [ ] **Step 4: Add the section to the template**

In `render/1`, after the Recovery codes `</section>` (the last section in the layout):

```heex
      <section class="mt-8 max-w-md">
        <h2 class="mb-3 text-[0.95rem] font-medium">Connected apps</h2>

        <ul :if={@authorized_clients != []} id="connected-apps" class="flex flex-col gap-2">
          <li
            :for={entry <- @authorized_clients}
            id={"connected-app-#{entry.client.id}"}
            class="flex items-center justify-between rounded-md border border-(--admin-border) px-3 py-2"
          >
            <div>
              <div class="text-[0.85rem] text-(--admin-text)">{entry.client.client_name}</div>
              <div class="text-[0.72rem] text-(--admin-text-subtle)">
                First connected {format_day(entry.first_connected_at)}
                · Last active {format_day(entry.last_active_at)}
                · {entry.grant_count} {if(entry.grant_count == 1, do: "grant", else: "grants")}
              </div>
            </div>
            <Components.button
              variant="secondary"
              phx-click="revoke_client"
              phx-value-id={entry.client.id}
              data-confirm={"Revoke #{entry.client.client_name}'s access?"}
            >
              Revoke
            </Components.button>
          </li>
        </ul>

        <p
          :if={@authorized_clients == []}
          id="connected-apps-empty"
          class="text-[0.82rem] text-(--admin-text-subtle)"
        >
          No apps have access.
        </p>
      </section>
```

- [ ] **Step 5: Run the tests, then the full gate**

Run: `mix test test/newton_web/live/admin/settings_live_test.exs test/newton/oauth_test.exs`
Expected: all PASS.

Run: `mix precommit`
Expected: clean.

- [ ] **Step 6: Format and commit**

```bash
mix format
git add lib/newton_web/live/admin/settings_live.ex test/newton_web/live/admin/settings_live_test.exs
git commit -m "Add a Connected apps section with grant revocation"
```
