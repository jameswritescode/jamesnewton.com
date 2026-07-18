# Timezone-Aware Analytics Design

**Goal:** View analytics stored as hourly UTC buckets and rendered in each
user's own timezone, selected in the admin settings tab.

**Context:** Supersedes the storage/query portions of
`2026-07-17-view-analytics-design.md` (all of it still uncommitted, so this is
an in-place rework, not a migration). The daily-bucket design baked
`Date.utc_today()` into the data at write time, which made the dashboard
highlight UTC's "today" (spotted live: Friday evening Pacific, Saturday
highlighted) and would have permanently mis-dayed all evening traffic.
Day-level rollups are lossy — once views collapse into a date, no query can
re-day them — so the fix is finer buckets, not a different write-time zone.

## Decisions

- **Hourly UTC buckets.** The rollup table keys on the truncated UTC hour, not
  a date. Still aggregated (no per-visitor anything), still tiny (≈24 rows per
  path per day), but query-time timezone conversion becomes possible: a "day"
  is computed at read time by shifting hours into the viewer's zone. UTC in
  storage, conversion on read — the standard shape, restored by granularity.
- **`users.timezone` drives all rendering.** IANA zone name on the user row,
  picked in settings, applied to the dashboard's "today", Mon–Sun frame,
  busiest-day/average, and all day-grouped queries. No site-level analytics
  timezone config — that concept dissolves entirely.
- **Known approximation:** zones with :30/:45 offsets (India, Nepal) misalign
  day edges by up to 45 minutes against hourly buckets. Accepted — noise at
  personal-blog scale; whole-hour zones are exact. DST days (23/25 hours) come
  out correct by construction.
- **`tzdata`** as the timezone database (`config :elixir, :time_zone_database,
  Tzdata.TimeZoneDatabase`). Default user timezone: `"America/Los_Angeles"`.
- **Dashboard date helpers become pure functions of an instant** (take a
  `DateTime`), so tests inject fixed moments instead of depending on the wall
  clock.

## Components

### 1. Storage rework (in-place edits to uncommitted files)

The existing uncommitted migration is rewritten (not appended to):

```elixir
create table(:hourly_views) do
  add :hour, :utc_datetime, null: false
  add :path, :string, null: false
  add :count, :integer, null: false, default: 0

  timestamps(type: :utc_datetime)
end

create unique_index(:hourly_views, [:hour, :path])
```

`Newton.Analytics.DailyView` becomes `Newton.Analytics.HourlyView` (fields
`hour`, `path`, `count`). Dev databases that already ran the old migration
roll it back first (`mix ecto.rollback`) — no deployed data exists.

### 2. `Newton.Analytics` — tz-aware API

```elixir
@spec record_views(%{optional({DateTime.t(), String.t()}) => pos_integer()}) :: :ok
# key is the truncated UTC hour; upsert-increment unchanged otherwise

@spec total_since(Date.t(), String.t()) :: non_neg_integer()
@spec total_all_time() :: non_neg_integer()
@spec top_paths(Date.t(), pos_integer(), String.t()) :: [%{path: String.t(), count: non_neg_integer()}]
@spec daily_totals(Date.t(), String.t()) :: [%{date: Date.t(), count: non_neg_integer()}]
@spec local_today(String.t()) :: Date.t()   # DateTime.now!(tz) |> DateTime.to_date()
```

Day derivation in queries via one shared fragment:

```elixir
defp local_date(tz) do
  dynamic([h], fragment("((? AT TIME ZONE 'UTC') AT TIME ZONE ?)::date", h.hour, ^tz))
end
```

`daily_totals/2` groups by that expression; `total_since/2` and `top_paths/3`
filter on it (`local_date >= since`). The `since` argument is a date in the
viewer's zone. `total_all_time/0` needs no zone (sum over everything).

### 3. `users.timezone`

- New migration: `add :timezone, :string, null: false, default: "America/Los_Angeles"`.
- `User` schema gains the field; a `timezone_changeset` validates the value
  resolves in the tz database (`Tzdata.zone_exists?/1`), rejecting anything
  else. Not in any `cast` used by registration params flow beyond the explicit
  settings action.
- `Newton.Accounts.update_user_timezone(user, attrs)` wraps it.

### 4. Settings tab picker

New section in `SettingsLive` (matching the existing `<section class="max-w-md">`
+ `Components.field`/`Components.button` pattern, placed above "Change
password"):

- A `<select>` over `Tzdata.zone_list()` (browsers type-to-search natively),
  current value selected, `phx-submit="save_timezone"`.
- On save: `Accounts.update_user_timezone/2`, flash "Timezone updated",
  re-assign `current_scope` so the dashboard picks it up immediately.

### 5. Collector

Buffer key becomes the truncated UTC hour:

```elixir
hour = %{DateTime.utc_now(:second) | minute: 0, second: 0}
key = {hour, path}
```

Nothing else changes — filters, flush, telemetry span, test-mode are untouched.

### 6. Dashboard

- `user_tz = @current_scope.user.timezone` at mount.
- `today = Analytics.local_today(user_tz)`; the Mon–Sun frame, future-day
  styling, and summary derive from it (helpers refactored to take the instant/
  zone rather than calling `Date.utc_today()`).
- All queries pass `user_tz`.

### 7. Seeds + inject script

Both write hour-keyed counts: each fake day spreads its views over a few
plausible UTC hours (e.g. 15:00–23:00, matching US-evening reading) so
converted days look organic. Deterministic as before.

## Out of scope

- Rendering non-analytics admin dates (post published_at etc.) in user tz —
  the setting exists now; sweep later if wanted.
- Timezone auto-detection from the browser.
- Public-facing anything.

## Error handling

- A timezone that fails `Tzdata.zone_exists?/1` never reaches the DB
  (changeset validation); the dashboard therefore always has a resolvable zone.
- `DateTime.now!/1` on a stored-valid zone cannot raise in practice; the
  default backstops new/legacy rows.

## Testing

1. **Conversion correctness (the heart of it):** insert hourly rows straddling
   UTC midnight (e.g. 2026-07-18 00:00 and 01:00 UTC); assert
   `daily_totals(..., "America/Los_Angeles")` counts them into 2026-07-17,
   while `"Etc/UTC"` counts them into the 18th. Same style for `total_since/2`
   window edges.
2. **Collector:** a counted request lands in the current UTC hour bucket;
   repeat-increment across flushes still holds.
3. **Settings:** selecting a zone persists and survives reload; a bogus value
   is rejected with a changeset error; saving re-frames the dashboard without
   re-login.
4. **Dashboard framing:** with helpers taking an injected instant, assert the
   Mon–Sun frame and "today" for a fixed `DateTime` in a zone where the local
   date differs from the UTC date.
5. Existing analytics/dashboard tests updated for the new signatures.
