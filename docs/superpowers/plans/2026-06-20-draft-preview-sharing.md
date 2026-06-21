# Draft Preview Sharing Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Let the author share an unpublished draft via an unguessable `?p=<token>` link on the normal post URL, toggled on/off from the editor drawer; sharing is draft-only and publishing clears the token.

**Architecture:** A nullable `preview_token` on `posts` (never mass-assignable), minted/cleared by `Newton.Blog` context functions and force-cleared on publish in the changeset. `PostController.show` honors a matching `?p` token (constant-time compare) to render that one draft, with a "Draft preview" banner and `noindex`. The editor's publish drawer gains a draft-only toggle that shows the shareable URL and a clipboard Copy button.

**Tech Stack:** Ecto migration, `Plug.Crypto.secure_compare`, Phoenix controller + HEEx, LiveView (admin editor), a JS hook in `admin.js`, vitest, `Phoenix.ConnTest`, Playwright (PORT=4001).

**Reference spec:** `docs/superpowers/specs/2026-06-20-draft-preview-sharing-design.md`

**Session constraints:** Commit signed (1Password; if it fails, commit `--no-gpg-sign` and re-sign later). Commit messages end with `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>`. Any server runs on `PORT=4001`, never 4000. Browser verification uses Playwright. Note: previewing the public 404/draft pages in dev needs `debug_errors: false` temporarily.

---

### Task 1: Data layer — token column, schema, context functions

**Files:**
- Create: `priv/repo/migrations/<ts>_add_preview_token_to_posts.exs`
- Modify: `lib/newton/blog/post.ex`
- Modify: `lib/newton/blog.ex`
- Test: `test/newton/blog_test.exs`

- [ ] **Step 1: Write the failing tests**

Append to `test/newton/blog_test.exs` (inside the top-level `describe`/module; mirror existing `Blog.create_post` usage):

```elixir
  describe "draft preview tokens" do
    test "enable_preview mints a token on a draft; disable clears it" do
      {:ok, draft} = Blog.create_post(%{slug: "d1", title: "D1", body_markdown: "x"})
      assert is_nil(draft.preview_token)

      {:ok, shared} = Blog.enable_preview(draft)
      assert is_binary(shared.preview_token)
      assert byte_size(shared.preview_token) >= 32

      {:ok, off} = Blog.disable_preview(shared)
      assert is_nil(off.preview_token)
    end

    test "enable_preview is a no-op on a published post" do
      {:ok, post} =
        Blog.create_post(%{slug: "p1", title: "P1", body_markdown: "x", published_at: ~U[2026-01-01 00:00:00Z]})

      {:ok, post} = Blog.enable_preview(post)
      assert is_nil(post.preview_token)
    end

    test "publishing a shared draft clears its token" do
      {:ok, draft} = Blog.create_post(%{slug: "d2", title: "D2", body_markdown: "x"})
      {:ok, shared} = Blog.enable_preview(draft)
      assert shared.preview_token

      {:ok, published} = Blog.update_post(shared, %{"published_at" => ~U[2026-01-01 00:00:00Z]})
      assert is_nil(published.preview_token)
    end

    test "get_post_by_preview_token returns the post only for the right token" do
      {:ok, draft} = Blog.create_post(%{slug: "d3", title: "D3", body_markdown: "x"})
      {:ok, shared} = Blog.enable_preview(draft)

      assert %{id: id} = Blog.get_post_by_preview_token("d3", shared.preview_token)
      assert id == shared.id
      assert is_nil(Blog.get_post_by_preview_token("d3", "wrong-token"))
      assert is_nil(Blog.get_post_by_preview_token("d3", ""))
    end
  end
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/newton/blog_test.exs`
Expected: FAIL — `preview_token` field and the new functions don't exist (compile/undefined errors).

- [ ] **Step 3: Generate the migration**

Run: `mix ecto.gen.migration add_preview_token_to_posts`
Then set its contents to:

```elixir
defmodule Newton.Repo.Migrations.AddPreviewTokenToPosts do
  use Ecto.Migration

  def change do
    alter table(:posts) do
      add :preview_token, :string
    end
  end
end
```

Run: `mix ecto.migrate`

- [ ] **Step 4: Add the field and clear-on-publish to the schema**

In `lib/newton/blog/post.ex`, add the field after `:published_at`:

```elixir
    field :published_at, :utc_datetime
    field :preview_token, :string
```

`preview_token` stays **out of** the `cast/2` list. Add a clear-on-publish step to the changeset pipeline (after `cast`):

```elixir
  def changeset(post, attrs) do
    post
    |> cast(attrs, [:slug, :title, :excerpt, :body_markdown, :published_at])
    |> clear_preview_token_when_published()
    |> ensure_body()
    |> validate_required([:slug, :title])
    |> unique_constraint(:slug)
    |> render_derived_fields()
  end

  # A published post never carries a preview token — every publish path runs the
  # changeset, so clearing it here covers them all.
  defp clear_preview_token_when_published(changeset) do
    if get_field(changeset, :published_at) do
      put_change(changeset, :preview_token, nil)
    else
      changeset
    end
  end
```

- [ ] **Step 5: Add the context functions**

In `lib/newton/blog.ex`, add (near the other post functions). Note these use a bare `change/2` so they don't run the full `changeset/2` (no body re-render):

```elixir
  @doc "Mint a preview token for a draft (idempotent). No-op once published."
  def enable_preview(%Post{published_at: nil} = post) do
    token = post.preview_token || (32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false))
    post |> Ecto.Changeset.change(preview_token: token) |> Repo.update()
  end

  def enable_preview(%Post{} = post), do: {:ok, post}

  @doc "Clear a post's preview token, invalidating any shared link."
  def disable_preview(%Post{} = post) do
    post |> Ecto.Changeset.change(preview_token: nil) |> Repo.update()
  end

  @doc "Fetch a post by slug only if `token` matches its preview token (constant-time)."
  def get_post_by_preview_token(slug, token) when is_binary(token) do
    case Repo.get_by(Post, slug: slug) do
      %Post{preview_token: stored} = post when is_binary(stored) ->
        if Plug.Crypto.secure_compare(token, stored), do: post, else: nil

      _ ->
        nil
    end
  end
```

- [ ] **Step 6: Run the tests to verify they pass**

Run: `mix test test/newton/blog_test.exs`
Expected: PASS.

- [ ] **Step 7: Commit**

```bash
git add priv/repo/migrations lib/newton/blog/post.ex lib/newton/blog.ex test/newton/blog_test.exs
git commit -m "$(cat <<'EOF'
Add draft preview tokens to the Blog context

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 2: Public preview render (controller, banner, noindex)

**Files:**
- Modify: `lib/newton_web/controllers/post_controller.ex`
- Modify: `lib/newton_web/controllers/post_html/show.html.heex`
- Modify: `lib/newton_web/components/layouts/root.html.heex`
- Modify: `assets/css/site.css` (banner style)
- Test: `test/newton_web/controllers/post_controller_test.exs`

- [ ] **Step 1: Write the failing tests**

Append to the `describe "draft visibility"` block in `test/newton_web/controllers/post_controller_test.exs` (it already sets up a `draft` with `slug: "secret-draft"`):

```elixir
    test "a draft is visible with a valid ?p token and carries noindex", %{conn: conn, draft: draft} do
      {:ok, draft} = Blog.enable_preview(draft)

      html = conn |> get(~p"/posts/#{draft.slug}?#{[p: draft.preview_token]}") |> html_response(200)
      assert html =~ draft.title
      assert html =~ "Draft preview"
      assert html =~ ~s(name="robots")
      assert html =~ "noindex"
    end

    test "a draft 404s with a wrong or missing ?p token", %{conn: conn, draft: draft} do
      {:ok, draft} = Blog.enable_preview(draft)

      assert_error_sent 404, fn -> get(conn, ~p"/posts/#{draft.slug}?#{[p: "nope"]}") end
      assert_error_sent 404, fn -> get(conn, ~p"/posts/#{draft.slug}") end
    end

    test "a published post renders without a token and is not noindex", %{conn: conn} do
      {:ok, _} =
        Blog.create_post(%{slug: "live-one", title: "Live One", body_markdown: "Body.", published_at: ~U[2026-01-01 00:00:00Z]})

      html = conn |> get(~p"/posts/live-one") |> html_response(200)
      assert html =~ "Live One"
      refute html =~ "noindex"
      refute html =~ "Draft preview"
    end
```

If the existing `setup` doesn't expose `draft` in the context map, ensure it returns `%{draft: draft}` (it creates `slug: "secret-draft"`).

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/newton_web/controllers/post_controller_test.exs`
Expected: FAIL — `?p` isn't honored (draft 404s even with a token), no banner, no robots meta.

- [ ] **Step 3: Honor the `?p` token in the controller**

Replace the `show/2` + `fetch_post/2` in `lib/newton_web/controllers/post_controller.ex`:

```elixir
  def show(conn, %{"slug" => slug} = params) do
    case fetch_post(conn.assigns.current_scope, slug, params["p"]) do
      {:preview, post} ->
        conn
        |> assign(:page_robots, "noindex")
        |> render(:show, page_title: post.title, post: post, preview: true)

      post ->
        render(conn, :show, page_title: post.title, post: post, preview: false)
    end
  end

  # A signed-in admin previews any post (drafts included); everyone else sees only
  # published posts, plus the single draft unlocked by a matching ?p token.
  defp fetch_post(%{user: %{}}, slug, _token), do: Blog.get_post_by_slug!(slug)

  defp fetch_post(_scope, slug, token) when is_binary(token) do
    case Blog.get_post_by_preview_token(slug, token) do
      %Post{} = post -> {:preview, post}
      nil -> Blog.get_published_post!(slug)
    end
  end

  defp fetch_post(_scope, slug, _token), do: Blog.get_published_post!(slug)
```

Add the alias at the top if missing: `alias Newton.Blog.Post`.

- [ ] **Step 4: Add the banner to the show template**

In `lib/newton_web/controllers/post_html/show.html.heex`, add the banner just inside `<Layouts.app>`:

```heex
<Layouts.app flash={@flash}>
  <div :if={@preview} class="preview-banner">
    Draft preview — this post isn't published. Link is private; please don't share it.
  </div>
  <article class="post">
```

- [ ] **Step 5: Add the conditional robots meta to the root layout**

In `lib/newton_web/components/layouts/root.html.heex`, add inside `<head>` (e.g. after the `<.live_title>` line):

```heex
    <meta :if={assigns[:page_robots]} name="robots" content={assigns[:page_robots]} />
```

- [ ] **Step 6: Style the banner**

In `assets/css/site.css`, near the `.post` rules:

```css
.preview-banner {
  max-width: var(--container-width);
  margin: 1rem auto 0;
  padding: 0.6rem 1rem;
  border: 1px solid rgba(var(--dot), 0.3);
  border-radius: var(--radius-md);
  font-size: 0.82rem;
  color: var(--text-muted);
  text-align: center;
}
```

- [ ] **Step 7: Run the tests to verify they pass**

Run: `mix test test/newton_web/controllers/post_controller_test.exs`
Expected: PASS.

- [ ] **Step 8: Commit**

```bash
git add lib/newton_web/controllers/post_controller.ex lib/newton_web/controllers/post_html/show.html.heex lib/newton_web/components/layouts/root.html.heex assets/css/site.css test/newton_web/controllers/post_controller_test.exs
git commit -m "$(cat <<'EOF'
Render shared draft previews via ?p token

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 3: Clipboard Copy hook

**Files:**
- Create: `assets/js/hooks/copy_text.js`
- Modify: `assets/js/admin.js` (register the hook)
- Test: `assets/js/hooks/copy_text.test.js`

- [ ] **Step 1: Write the failing test**

Create `assets/js/hooks/copy_text.test.js`:

```js
import {describe, it, expect, vi, afterEach} from "vitest"
import {CopyText} from "./copy_text"

function mount(el) {
  const hook = {el}
  Object.setPrototypeOf(hook, CopyText)
  hook.mounted()
  return hook
}

afterEach(() => vi.restoreAllMocks())

describe("CopyText", () => {
  it("writes the data-clipboard-text value to the clipboard on click", async () => {
    const writeText = vi.fn().mockResolvedValue()
    vi.stubGlobal("navigator", {clipboard: {writeText}})

    const btn = document.createElement("button")
    btn.dataset.clipboardText = "https://example.com/posts/x?p=tok"
    mount(btn)

    btn.dispatchEvent(new MouseEvent("click", {bubbles: true}))

    expect(writeText).toHaveBeenCalledWith("https://example.com/posts/x?p=tok")
    vi.unstubAllGlobals()
  })
})
```

- [ ] **Step 2: Run the test to verify it fails**

Run: `cd assets && pnpm vitest run js/hooks/copy_text.test.js`
Expected: FAIL — `./copy_text` doesn't exist.

- [ ] **Step 3: Implement the hook**

Create `assets/js/hooks/copy_text.js`:

```js
// Copies the value of `data-clipboard-text` to the clipboard on click, with a
// brief "Copied" affordance via the data-copied attribute (CSS can react).
export const CopyText = {
  mounted() {
    this.el.addEventListener("click", () => {
      const text = this.el.dataset.clipboardText
      if (!text) return
      navigator.clipboard.writeText(text).then(() => {
        this.el.setAttribute("data-copied", "true")
        clearTimeout(this._t)
        this._t = setTimeout(() => this.el.removeAttribute("data-copied"), 1500)
      })
    })
  },

  destroyed() {
    clearTimeout(this._t)
  },
}
```

- [ ] **Step 4: Register the hook in `admin.js`**

In `assets/js/admin.js`, import and add it to the hooks map:

```js
import {CopyText} from "./hooks/copy_text"
```

and add `CopyText` to the `hooks: {...}` object:

```js
  hooks: {...colocatedHooks, AdminTheme, AdminNav, UnsavedGuard, FlashDismiss, MarkdownEditor, ImageDimensions, SortableGrid, CopyText},
```

- [ ] **Step 5: Run the test to verify it passes**

Run: `cd assets && pnpm vitest run js/hooks/copy_text.test.js`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add assets/js/hooks/copy_text.js assets/js/hooks/copy_text.test.js assets/js/admin.js
git commit -m "$(cat <<'EOF'
Add a clipboard CopyText hook

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 4: Editor drawer control + events

**Files:**
- Modify: `lib/newton_web/live/admin/post_live/editor.ex` (events + drawer markup)
- Test: `test/newton_web/live/admin/post_editor_live_test.exs`

- [ ] **Step 1: Write the failing tests**

Append to `test/newton_web/live/admin/post_editor_live_test.exs`:

```elixir
  test "enabling and disabling the preview link on a saved draft", %{conn: conn} do
    {view, post} = open_draft(conn)

    refute render(view) =~ "/posts/#{post.slug}?p="

    view |> element("button", "Enable preview link") |> render_click()

    updated = Newton.Blog.get_post!(post.id)
    assert updated.preview_token
    assert render(view) =~ "?p=#{updated.preview_token}"

    view |> element("button", "Turn off preview link") |> render_click()
    assert is_nil(Newton.Blog.get_post!(post.id).preview_token)
  end

  test "the preview control is hidden once a post is published", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{
        title: "Pub",
        slug: "pub-preview",
        body_markdown: "b",
        published_at: ~U[2026-01-01 00:00:00Z]
      })

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")
    view |> element("button", "Settings") |> render_click()

    refute has_element?(view, "button", "Enable preview link")
  end
```

(The existing `open_draft/2` helper creates a saved draft and returns `{view, post}`. The drawer opens via the existing "Settings" button used in other tests; if the preview control is inside the drawer, click "Settings" first in the enable/disable test too — match how other drawer tests open it.)

- [ ] **Step 2: Run the tests to verify they fail**

Run: `mix test test/newton_web/live/admin/post_editor_live_test.exs`
Expected: FAIL — no "Enable preview link" control / events yet.

- [ ] **Step 3: Add the events**

In `lib/newton_web/live/admin/post_live/editor.ex`, add near the other `handle_event` clauses:

```elixir
  def handle_event("enable_preview", _params, socket) do
    {:ok, post} = Blog.enable_preview(socket.assigns.post)
    {:noreply, assign(socket, :post, post)}
  end

  def handle_event("disable_preview", _params, socket) do
    {:ok, post} = Blog.disable_preview(socket.assigns.post)
    {:noreply, assign(socket, :post, post)}
  end
```

- [ ] **Step 4: Add the drawer control**

In the publish drawer (`lib/newton_web/live/admin/post_live/editor.ex`), insert this **before** the `<Components.drawer_footer ...>` and after the "Reading time" block. It shows only for drafts:

```heex
        <div :if={is_nil(@published_at)} class="border-t border-(--admin-border) pt-3">
          <div class="mb-1 text-[0.78rem] font-medium text-(--admin-text)">Preview link</div>
          <%= cond do %>
            <% is_nil(@post.id) -> %>
              <p class="text-[0.75rem] text-(--admin-text-subtle)">
                Save the draft to share a preview.
              </p>
            <% @post.preview_token -> %>
              <input
                id="preview-link-url"
                type="text"
                readonly
                value={url(~p"/posts/#{@post.slug}?#{[p: @post.preview_token]}")}
                class="w-full rounded-md border border-(--admin-border) bg-(--admin-surface) px-2 py-1 text-[0.75rem] text-(--admin-text-muted) focus:outline-none"
              />
              <div class="mt-2 flex gap-2">
                <button
                  id="copy-preview-link"
                  type="button"
                  phx-hook="CopyText"
                  data-clipboard-text={url(~p"/posts/#{@post.slug}?#{[p: @post.preview_token]}")}
                  class="rounded-md bg-(--admin-accent) px-3 py-1 text-[0.75rem] font-medium text-white hover:bg-(--admin-accent-hover)"
                >
                  Copy
                </button>
                <button
                  type="button"
                  phx-click="disable_preview"
                  class="rounded-md border border-(--admin-border) px-3 py-1 text-[0.75rem] hover:bg-(--admin-accent-soft)"
                >
                  Turn off preview link
                </button>
              </div>
            <% true -> %>
              <button
                type="button"
                phx-click="enable_preview"
                class="rounded-md border border-(--admin-border) px-3 py-1 text-[0.75rem] hover:bg-(--admin-accent-soft)"
              >
                Enable preview link
              </button>
          <% end %>
        </div>
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `mix test test/newton_web/live/admin/post_editor_live_test.exs`
Expected: PASS.

- [ ] **Step 6: Commit**

```bash
git add lib/newton_web/live/admin/post_live/editor.ex test/newton_web/live/admin/post_editor_live_test.exs
git commit -m "$(cat <<'EOF'
Add the draft preview link control to the editor

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

### Task 5: Full verification + e2e

- [ ] **Step 1: Run the full precommit suite**

Run: `mix precommit`
Expected: PASS — format, compile, credo, dialyzer, full `mix test`, and the JS suite all green. Fix any findings (do not disable linters).

- [ ] **Step 2: Playwright e2e of the share round-trip**

Temporarily set `config/dev.exs` `debug_errors: false` (revert after). Build assets, start a server on `PORT=4001`. Create `assets/preview_e2e.mjs` that:
1. logs in (the `#login_form_password` flow), opens a draft editor, opens the Settings drawer, clicks "Enable preview link", and reads the `#preview-link-url` value;
2. in a **fresh, unauthenticated** browser context, visits that URL → asserts the draft body and the "Draft preview" banner render (200);
3. visits the same path **without** `?p` → asserts 404 (or the published-only behavior);
4. back in the admin context, clicks "Turn off preview link", then re-visits the saved URL in the anon context → asserts it no longer renders the draft.

Run: `cd assets && node preview_e2e.mjs`. Expected: all assertions pass.

- [ ] **Step 3: Clean up**

Remove `assets/preview_e2e.mjs`, stop the PORT=4001 server, and revert `config/dev.exs` `debug_errors` to `true` (confirm it's not staged).

- [ ] **Step 4: Commit any verification-driven fixes**

Only if Step 1/2 surfaced changes:

```bash
git add -A
git commit -m "$(cat <<'EOF'
Fix issues found verifying draft preview sharing

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>
EOF
)"
```

---

## Self-review notes

- **Spec coverage:** `?p` param + constant-time match (Task 1 `get_post_by_preview_token`, Task 2 controller); per-post nullable `preview_token` not mass-assignable (Task 1 schema); clear-on-publish in changeset (Task 1); draft-only control hidden when published + disabled until saved (Task 4 `cond`); banner + `noindex` (Task 2); enable/disable toggle + URL + Copy (Tasks 3–4); tests across context/controller/editor/JS (Tasks 1–4) and e2e (Task 5). Out-of-scope items (named links, expiry, comments, Referer hardening) intentionally omitted.
- **Type/name consistency:** `enable_preview/1`, `disable_preview/1`, `get_post_by_preview_token/2` defined in Task 1 and called identically in Tasks 2 & 4; `preview_token` field name consistent; the editor events `enable_preview`/`disable_preview` match the `phx-click` values in the markup; `data-clipboard-text` set in Task 4 matches the `CopyText` hook's read in Task 3; `?#{[p: token]}` query form used in both controller tests and the editor URL.
- **URL helper:** `url(~p"/posts/#{slug}?#{[p: token]}")` yields the absolute, shareable URL; the controller reads `params["p"]`.
