# Timezone-Aware Analytics Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Rework the (uncommitted) view-analytics storage to hourly UTC buckets, add a per-user timezone setting with a picker in the admin settings tab, and render the dashboard in the viewer's zone.

**Architecture:** `hourly_views` keys on the truncated UTC hour; queries derive local days at read time via a `AT TIME ZONE` fragment parameterized by the viewer's `users.timezone` (IANA name, validated via `tzdata`, picked in `SettingsLive`). The collector stamps buckets with the UTC hour; the dashboard frames "today"/Mon–Sun in the user's zone.

**Tech Stack:** `tzdata` (new dep), Ecto fragments for tz conversion, existing collector/dashboard from the uncommitted analytics feature.

**Spec:** `docs/superpowers/specs/2026-07-17-timezone-analytics-design.md`

## Global Constraints

- **NO GIT COMMITS.** Owner is remote (signing unavailable). Never run `git add`/`git commit`; leave everything in the working tree.
- **Rework in place:** the analytics feature is uncommitted. The daily_views migration file gets REWRITTEN (and renamed), not superseded by a new migration. **Rollback order matters:** `mix ecto.rollback` BEFORE rewriting the migration file, or the old table can't be dropped cleanly. (The dev DB's analytics rows are fake — losing them is expected.)
- The day-conversion fragment, exactly: `((? AT TIME ZONE 'UTC') AT TIME ZONE ?)::date` applied to `hour` and the zone string. Defined ONCE as a private macro, used everywhere.
- Default timezone everywhere it appears: `"America/Los_Angeles"`.
- Timezone values are IANA names validated with `Tzdata.zone_exists?/1` — invalid values must never reach the DB.
- The telemetry handler in the collector must remain raise-proof; only its bucket key changes.
- Dashboard date helpers become pure functions of an injected instant/zone (no bare `Date.utc_today()` left in `dashboard_live.ex`).
- The owner's dev server is running on port 4000 sharing this tree — never start anything on port 4000; use PORT=4001 if a server is needed.
- No narrating comments; domain `@spec`s; `mix format` clean per file as you go.
- Finish with `mix precommit` (Task 3, final step).

---

### Task 1: Hourly storage + tz-aware `Newton.Analytics`

**Files:**
- Modify (rewrite + rename): `priv/repo/migrations/20260717230802_create_daily_views.exs` → `priv/repo/migrations/20260717230802_create_hourly_views.exs`
- Modify (rewrite + rename): `lib/newton/analytics/daily_view.ex` → `lib/newton/analytics/hourly_view.ex`
- Modify: `lib/newton/analytics.ex` (full rework below)
- Modify: `mix.exs` (add tzdata), `config/config.exs` (time zone database)
- Test: `test/newton/analytics_test.exs` (rewrite)

**Interfaces:**
- Produces (Tasks 2/3 rely on these exact signatures):
  - `Newton.Analytics.record_views(%{optional({DateTime.t(), String.t()}) => pos_integer()}) :: :ok` — key is the truncated UTC hour
  - `Newton.Analytics.local_today(String.t()) :: Date.t()`
  - `Newton.Analytics.total_since(Date.t(), String.t()) :: non_neg_integer()`
  - `Newton.Analytics.total_all_time() :: non_neg_integer()`
  - `Newton.Analytics.top_paths(Date.t(), pos_integer(), String.t()) :: [%{path: String.t(), count: non_neg_integer()}]`
  - `Newton.Analytics.daily_totals(Date.t(), String.t()) :: [%{date: Date.t(), count: non_neg_integer()}]`

- [ ] **Step 1: Rollback the old migration FIRST**

Run: `mix ecto.migrations | tail -3` — confirm `create_daily_views` is the latest and `up`.
Run: `mix ecto.rollback`
Expected: `daily_views` dropped.

- [ ] **Step 2: Add tzdata**

`mix.exs` deps, after `{:plug_cowboy, "~> 2.7"}`:

```elixir
      {:plug_cowboy, "~> 2.7"},
      {:tzdata, "~> 1.1"}
```

`config/config.exs`, before the phoenix_seo block:

```elixir
config :elixir, :time_zone_database, Tzdata.TimeZoneDatabase
```

Run: `mix deps.get`
Expected: resolves tzdata 1.1.x.

- [ ] **Step 3: Rewrite the migration (rename file and module)**

`git` is off-limits; use plain `mv`. New content of
`priv/repo/migrations/20260717230802_create_hourly_views.exs`:

```elixir
defmodule Newton.Repo.Migrations.CreateHourlyViews do
  use Ecto.Migration

  def change do
    create table(:hourly_views) do
      add :hour, :utc_datetime, null: false
      add :path, :string, null: false
      add :count, :integer, null: false, default: 0

      timestamps(type: :utc_datetime)
    end

    create unique_index(:hourly_views, [:hour, :path])
  end
end
```

Run: `mix ecto.migrate`
Expected: `hourly_views` created.

- [ ] **Step 4: Rewrite the failing tests**

Replace `test/newton/analytics_test.exs` entirely:

```elixir
defmodule Newton.AnalyticsTest do
  use Newton.DataCase, async: true

  alias Newton.Analytics

  @la "America/Los_Angeles"
  @utc "Etc/UTC"

  test "record_views inserts new hourly buckets and increments existing ones" do
    hour = ~U[2026-07-18 12:00:00Z]

    :ok = Analytics.record_views(%{{hour, "/posts/hello"} => 2, {hour, "/photos"} => 1})
    :ok = Analytics.record_views(%{{hour, "/posts/hello"} => 3})

    assert Analytics.total_all_time() == 6
  end

  test "record_views with an empty map is a no-op" do
    assert Analytics.record_views(%{}) == :ok
    assert Analytics.total_all_time() == 0
  end

  test "daily_totals groups hours into the viewer's local days" do
    # 00:30 and 01:00 UTC on the 18th are still the evening of the 17th in LA.
    :ok =
      Analytics.record_views(%{
        {~U[2026-07-18 00:00:00Z], "/posts/a"} => 2,
        {~U[2026-07-18 01:00:00Z], "/posts/a"} => 3,
        {~U[2026-07-18 12:00:00Z], "/posts/a"} => 7
      })

    assert [%{date: ~D[2026-07-17], count: 5}, %{date: ~D[2026-07-18], count: 7}] =
             Analytics.daily_totals(~D[2026-07-01], @la)

    assert [%{date: ~D[2026-07-18], count: 12}] = Analytics.daily_totals(~D[2026-07-01], @utc)
  end

  test "total_since applies the zone's day boundary to the window" do
    :ok =
      Analytics.record_views(%{
        {~U[2026-07-18 00:00:00Z], "/posts/a"} => 5,
        {~U[2026-07-18 12:00:00Z], "/posts/a"} => 7
      })

    assert Analytics.total_since(~D[2026-07-18], @utc) == 12
    assert Analytics.total_since(~D[2026-07-18], @la) == 7
  end

  test "top_paths filters by local day, orders by total, and honors the limit" do
    :ok =
      Analytics.record_views(%{
        {~U[2026-07-18 00:00:00Z], "/posts/old-evening"} => 9,
        {~U[2026-07-18 12:00:00Z], "/posts/b"} => 4,
        {~U[2026-07-18 13:00:00Z], "/posts/c"} => 6
      })

    assert [%{path: "/posts/c", count: 6}, %{path: "/posts/b", count: 4}] =
             Analytics.top_paths(~D[2026-07-18], 2, @la)
  end

  test "local_today returns the date in the given zone" do
    assert Analytics.local_today(@utc) == DateTime.utc_now() |> DateTime.to_date()
    assert %Date{} = Analytics.local_today(@la)
  end
end
```

- [ ] **Step 5: Run tests to verify they fail**

Run: `mix test test/newton/analytics_test.exs`
Expected: FAIL — `HourlyView`/new signatures undefined.

- [ ] **Step 6: Rewrite schema + context**

`mv lib/newton/analytics/daily_view.ex lib/newton/analytics/hourly_view.ex`, content:

```elixir
defmodule Newton.Analytics.HourlyView do
  @moduledoc "One UTC hour's view count for one public path."
  use Ecto.Schema

  schema "hourly_views" do
    field :hour, :utc_datetime
    field :path, :string
    field :count, :integer, default: 0

    timestamps(type: :utc_datetime)
  end
end
```

`lib/newton/analytics.ex` full replacement:

```elixir
defmodule Newton.Analytics do
  @moduledoc """
  Server-side view analytics: hourly UTC rollups, grouped into days in the
  viewer's timezone at query time.
  """
  import Ecto.Query

  alias Newton.Analytics.HourlyView
  alias Newton.Repo

  defmacrop local_date(hour, tz) do
    quote do
      fragment("((? AT TIME ZONE 'UTC') AT TIME ZONE ?)::date", unquote(hour), unquote(tz))
    end
  end

  @spec record_views(%{optional({DateTime.t(), String.t()}) => pos_integer()}) :: :ok
  def record_views(counts) when map_size(counts) == 0, do: :ok

  def record_views(counts) do
    now = DateTime.utc_now(:second)

    rows =
      for {{hour, path}, count} <- counts do
        %{hour: hour, path: path, count: count, inserted_at: now, updated_at: now}
      end

    Repo.insert_all(HourlyView, rows,
      conflict_target: [:hour, :path],
      on_conflict:
        from(h in HourlyView,
          update: [
            inc: [count: fragment("EXCLUDED.count")],
            set: [updated_at: fragment("EXCLUDED.updated_at")]
          ]
        )
    )

    :ok
  end

  @spec local_today(String.t()) :: Date.t()
  def local_today(tz), do: tz |> DateTime.now!() |> DateTime.to_date()

  @spec total_since(Date.t(), String.t()) :: non_neg_integer()
  def total_since(date, tz) do
    Repo.one(
      from h in HourlyView,
        where: local_date(h.hour, ^tz) >= ^date,
        select: coalesce(sum(h.count), 0)
    )
  end

  @spec total_all_time() :: non_neg_integer()
  def total_all_time do
    Repo.one(from h in HourlyView, select: coalesce(sum(h.count), 0))
  end

  @spec top_paths(Date.t(), pos_integer(), String.t()) ::
          [%{path: String.t(), count: non_neg_integer()}]
  def top_paths(since, limit, tz) do
    Repo.all(
      from h in HourlyView,
        where: local_date(h.hour, ^tz) >= ^since,
        group_by: h.path,
        order_by: [desc: sum(h.count)],
        limit: ^limit,
        select: %{path: h.path, count: sum(h.count)}
    )
  end

  @spec daily_totals(Date.t(), String.t()) :: [%{date: Date.t(), count: non_neg_integer()}]
  def daily_totals(since, tz) do
    Repo.all(
      from h in HourlyView,
        where: local_date(h.hour, ^tz) >= ^since,
        group_by: local_date(h.hour, ^tz),
        order_by: local_date(h.hour, ^tz),
        select: %{date: local_date(h.hour, ^tz), count: sum(h.count)}
    )
  end
end
```

- [ ] **Step 7: Run tests to verify they pass**

Run: `mix test test/newton/analytics_test.exs`
Expected: 6 tests, 0 failures. (If the `::date` select comes back as a string
instead of `%Date{}`, the fragment cast is wrong — fix the fragment, do not
convert in Elixir.)

**Do NOT commit. Report and stop here.** (Note: `test/newton/analytics/collector_test.exs` and the dashboard tests are now broken — Task 3 fixes them; run only the analytics test file here.)

---

### Task 2: `users.timezone` + settings picker

**Files:**
- Create: migration via `mix ecto.gen.migration add_timezone_to_users`
- Modify: `lib/newton/accounts/user.ex` (field + changeset)
- Modify: `lib/newton/accounts.ex` (update function)
- Modify: `lib/newton_web/live/admin/settings_live.ex` (mount assigns, event, section)
- Test: `test/newton_web/live/admin/settings_timezone_test.exs` (new)

**Interfaces:**
- Consumes: `Tzdata.zone_exists?/1`, `Tzdata.zone_list/0` (Task 1's dep).
- Produces: `user.timezone :: String.t()` (Task 3 reads it via `current_scope.user.timezone`); `Newton.Accounts.update_user_timezone(User.t(), map()) :: {:ok, User.t()} | {:error, Ecto.Changeset.t()}`.

- [ ] **Step 1: Migration**

Run: `mix ecto.gen.migration add_timezone_to_users`, then `change/0`:

```elixir
  def change do
    alter table(:users) do
      add :timezone, :string, null: false, default: "America/Los_Angeles"
    end
  end
```

Run: `mix ecto.migrate`

- [ ] **Step 2: Write the failing tests**

Create `test/newton_web/live/admin/settings_timezone_test.exs`:

```elixir
defmodule NewtonWeb.Admin.SettingsTimezoneTest do
  use NewtonWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  setup %{conn: conn} do
    user = user_fixture()
    %{conn: log_in_user(conn, user), user: user}
  end

  test "the timezone select shows the current value and saves a new one", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _html} = live(conn, ~p"/admin/settings")

    assert has_element?(view, ~s(#timezone-form option[selected][value="America/Los_Angeles"]))

    view
    |> form("#timezone-form", user: %{timezone: "Europe/Lisbon"})
    |> render_submit()

    assert render(view) =~ "Timezone updated"
    assert Newton.Accounts.get_user!(user.id).timezone == "Europe/Lisbon"
  end

  test "an unknown timezone is rejected", %{conn: conn, user: user} do
    {:ok, _view, _html} = live(conn, ~p"/admin/settings")

    assert {:error, changeset} =
             Newton.Accounts.update_user_timezone(user, %{"timezone" => "Mars/Olympus_Mons"})

    assert %{timezone: ["is not a known timezone"]} = errors_on(changeset)
  end
end
```

(If `Newton.Accounts.get_user!/1` doesn't exist, use
`Newton.Repo.get!(Newton.Accounts.User, user.id)` in the assertion instead —
check first, don't add a context function for a test.)

- [ ] **Step 3: Run tests to verify they fail**

Run: `mix test test/newton_web/live/admin/settings_timezone_test.exs`
Expected: FAIL — no `#timezone-form`, no `update_user_timezone/2`.

- [ ] **Step 4: Schema + context**

`lib/newton/accounts/user.ex` — add after the existing fields:

```elixir
    field :timezone, :string, default: "America/Los_Angeles"
```

and a changeset (near the other changesets):

```elixir
  def timezone_changeset(user, attrs) do
    user
    |> cast(attrs, [:timezone])
    |> validate_required([:timezone])
    |> validate_change(:timezone, fn :timezone, tz ->
      if Tzdata.zone_exists?(tz), do: [], else: [timezone: "is not a known timezone"]
    end)
  end
```

`lib/newton/accounts.ex`:

```elixir
  @spec update_user_timezone(%User{}, map()) :: {:ok, %User{}} | {:error, Ecto.Changeset.t()}
  def update_user_timezone(%User{} = user, attrs) do
    user |> User.timezone_changeset(attrs) |> Repo.update()
  end
```

(Match the file's existing `@spec` style; alias `User` is already there.)

- [ ] **Step 5: Settings section**

`lib/newton_web/live/admin/settings_live.ex`:

Mount gains:

```elixir
     |> assign(:timezone_form, timezone_form(user))
```

with:

```elixir
  defp timezone_form(user), do: to_form(Newton.Accounts.User.timezone_changeset(user, %{}), as: :user)
```

New event (near `save_password`):

```elixir
  def handle_event("save_timezone", %{"user" => params}, socket) do
    case Accounts.update_user_timezone(socket.assigns.user, params) do
      {:ok, user} ->
        {:noreply,
         socket
         |> assign(:user, user)
         |> assign(:timezone_form, timezone_form(user))
         |> put_flash(:info, "Timezone updated.")}

      {:error, changeset} ->
        {:noreply, assign(socket, :timezone_form, to_form(changeset, as: :user))}
    end
  end
```

Template — new section ABOVE the "Change password" section, matching its
structure:

```heex
      <section class="mb-8 max-w-md">
        <h2 class="mb-3 text-[0.95rem] font-medium">Timezone</h2>
        <.form for={@timezone_form} id="timezone-form" phx-submit="save_timezone">
          <Components.field
            field={@timezone_form[:timezone]}
            type="select"
            label="Analytics and dashboard render in this timezone"
            options={Tzdata.zone_list()}
          />
          <div class="mt-3">
            <Components.button type="submit">Save timezone</Components.button>
          </div>
        </.form>
      </section>
```

(If the LiveView's session user isn't refreshed elsewhere: this page assigns
`:user`; the dashboard reads `current_scope` fresh per mount, so no extra
scope plumbing is needed.)

- [ ] **Step 6: Run tests to verify they pass**

Run: `mix test test/newton_web/live/admin/settings_timezone_test.exs`
Expected: 2 tests, 0 failures.

**Do NOT commit. Report and stop here.**

---

### Task 3: Collector hour buckets + dashboard tz + seeds + suite repair

**Files:**
- Modify: `lib/newton/analytics/collector.ex` (bucket key)
- Modify: `lib/newton_web/live/admin/dashboard_live.ex` (tz plumbing)
- Modify: `priv/repo/seeds.exs` (hour-keyed fake data)
- Test: `test/newton/analytics/collector_test.exs`, `test/newton_web/live/admin/dashboard_views_test.exs` (update both)

**Interfaces:**
- Consumes: everything Task 1 produces; `current_scope.user.timezone` (Task 2).

- [ ] **Step 1: Collector bucket key**

In `lib/newton/analytics/collector.ex`, `handle_cast`:

```elixir
  @impl true
  def handle_cast({:view, path}, state) do
    hour = %{DateTime.utc_now(:second) | minute: 0, second: 0}
    key = {hour, path}
    {:noreply, %{state | buffer: Map.update(state.buffer, key, 1, &(&1 + 1))}}
  end
```

- [ ] **Step 2: Dashboard tz plumbing**

In `lib/newton_web/live/admin/dashboard_live.ex`:

Mount — replace the three analytics assigns and add the frame assigns:

```elixir
    user_tz = socket.assigns.current_scope.user.timezone
    today = Newton.Analytics.local_today(user_tz)

    {:ok,
     socket
     ...existing non-analytics assigns unchanged...
     |> assign(:local_today, today)
     |> assign(:views_week, Newton.Analytics.total_since(Date.add(today, -6), user_tz))
     |> assign(:views_total, Newton.Analytics.total_all_time())
     |> assign(:top_posts, top_posts(today, user_tz))
     |> assign(:week_series, week_series(today, user_tz))}
```

Helpers become pure in the instant:

```elixir
  defp top_posts(today, tz) do
    titles = Map.new(Newton.Blog.list_published_posts(), &{&1.slug, &1.title})

    today
    |> Date.add(-6)
    |> Newton.Analytics.top_paths(20, tz)
    |> Enum.flat_map(fn %{path: path, count: count} ->
      case path do
        "/posts/" <> slug ->
          [
            %{
              slug: slug,
              count: count,
              title: Map.get(titles, slug, path),
              exists?: Map.has_key?(titles, slug)
            }
          ]

        _ ->
          []
      end
    end)
    |> Enum.take(5)
  end

  defp week_series(today, tz) do
    monday = Date.beginning_of_week(today)
    totals = Map.new(Newton.Analytics.daily_totals(monday, tz), &{&1.date, &1.count})

    for offset <- 0..6 do
      date = Date.add(monday, offset)
      %{date: date, count: Map.get(totals, date, 0), future?: Date.compare(date, today) == :gt}
    end
  end
```

Template: the week-bar `cond` compares `day.date == @local_today` instead of
`Date.utc_today()`. No other template changes. Grep the file afterward:
`grep -c 'utc_today' lib/newton_web/live/admin/dashboard_live.ex` must print 0.

- [ ] **Step 3: Seeds**

Replace the analytics section of `priv/repo/seeds.exs` (aliases: `DailyView` →
`HourlyView`; reset `Repo.delete_all(HourlyView)`), and generate hour-keyed
counts — each fake day's total split across three UTC evening/midday hours:

```elixir
views =
  for days_ago <- 0..29, {path, weight} <- view_weights, reduce: %{} do
    acc ->
      date = Date.add(today, -days_ago)
      jitter = :erlang.phash2({path, date}, weight + 1)
      aggregator_spike = if days_ago in 3..5 and path =~ "the-quiet-shift", do: 40, else: 0
      total = weight + jitter + aggregator_spike

      early = div(total, 3)
      mid = div(total, 3)
      late = total - early - mid

      [{15, early}, {19, mid}, {23, late}]
      |> Enum.reject(fn {_h, n} -> n == 0 end)
      |> Enum.reduce(acc, fn {h, n}, acc ->
        hour = DateTime.new!(date, Time.new!(h, 0, 0), "Etc/UTC")
        Map.update(acc, {hour, path}, n, &(&1 + n))
      end)
  end

:ok = Analytics.record_views(views)
```

Final `IO.puts` counts `Repo.aggregate(HourlyView, :count)` "view rows".

- [ ] **Step 4: Repair the collector tests**

`test/newton/analytics/collector_test.exs` — only `count_for/1` changes
signature-wise (top_paths arity):

```elixir
  defp count_for(path) do
    Analytics.top_paths(Date.add(Date.utc_today(), -2), 100, "Etc/UTC")
    |> Enum.find_value(0, fn %{path: p, count: c} -> if p == path, do: c end)
  end
```

(`-2` days and UTC: the collector stamps UTC hours, so a UTC window always
contains them regardless of when the test runs.)

- [ ] **Step 5: Repair the dashboard tests**

`test/newton_web/live/admin/dashboard_views_test.exs` — seeding writes hours
that are unambiguously "today" in the default LA zone regardless of run time:

```elixir
  defp la_hour(date, hour) do
    DateTime.new!(date, Time.new!(hour, 0, 0), "America/Los_Angeles")
    |> DateTime.shift_zone!("Etc/UTC")
    |> then(&%{&1 | minute: 0, second: 0})
  end

  defp seed_views do
    today = Newton.Analytics.local_today("America/Los_Angeles")

    {:ok, _} =
      Newton.Blog.create_post(%{
        slug: "top-post",
        title: "The Top Post",
        body_markdown: "Body.",
        published_at: DateTime.utc_now()
      })

    :ok =
      Newton.Analytics.record_views(%{
        {la_hour(today, 12), "/posts/top-post"} => 7,
        {la_hour(today, 13), "/posts/deleted-post"} => 3,
        {la_hour(Date.add(today, -30), 12), "/photos"} => 10
      })
  end
```

The week-panel test's elapsed-days derivation uses the LA today:

```elixir
    today = Newton.Analytics.local_today("America/Los_Angeles")
    elapsed_days = Date.diff(today, Date.beginning_of_week(today)) + 1

    :ok = Newton.Analytics.record_views(%{{la_hour(today, 12), "/posts/busy"} => 14})
```

and its assertions keep `Calendar.strftime(today, "%A")` /
`"#{div(14, elapsed_days)}/day average"` with that `today`.
(Note `la_hour/2` shifting noon avoids DST-transition ambiguity — noon always
exists and maps into the same LA day.)

- [ ] **Step 6: Run the repaired suites**

Run: `mix test test/newton/analytics/collector_test.exs test/newton_web/live/admin/dashboard_views_test.exs test/newton/analytics_test.exs`
Expected: all pass.

- [ ] **Step 7: Full gate**

Run: `mix precommit`
Expected: clean (dialyzer: 3 known phoenix_seo skips). Fix anything raised.

**Do NOT commit. Report and stop here.**
