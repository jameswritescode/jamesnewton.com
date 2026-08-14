# Reading page: series grouping

Group books that belong to a series into one visual block on the public
`/reading` page, without adding heavy chrome to the site or the admin.

## Decision summary

Three grouping treatments were mocked against the site's real reading-page
styles; the approved one is **pull together**: a series forms a single group
positioned in the feed where its newest entry falls, and older entries in the
series move up into it. The rest of the feed stays chronological.

Series membership is a free-form string on the entry, with autocomplete of
existing series names in the admin form (native `<datalist>`).

## Data model

- Migration: add `series` (`:string`, nullable) to `reading_entries`.
- `Entry.changeset/2` casts `series` as optional and normalizes blank/whitespace
  to `nil`, so clearing the field removes the entry from its group and `""`
  never becomes a group key.
- The grouping key is the exact series string. Typos split groups; accepted for
  a single-operator site, mitigated by autocomplete.

## Context (`Newton.Reading`)

Two new functions; existing functions are untouched (`list_entries/0` keeps the
admin list flat).

**`series_names/0`** — distinct non-nil series names, sorted ascending. Feeds
the admin autocomplete.

**`feed_entries/0`** — the public feed structure:

1. Sort all entries as today: `finished_at` desc, in-progress (nil) first.
2. Walk the sorted list. The first time a series name appears, emit a group
   containing **all** entries of that series (newest first, in-progress first
   within the group); later occurrences of that series are skipped.
3. Entries with no series pass through unchanged.
4. A series with exactly one entry passes through as a plain entry — no group
   chrome for a group of one.

Return shape: a list mixing `%Entry{}` structs and `{:series, name, entries}`
tuples, in feed order. Grouping is pure data logic, unit-testable without
templates.

Group label data: when every entry in a group has the same author, the label is
"Series · Author" and per-entry author lines are dropped; when authors differ,
the label is the series name alone and each entry keeps "by Author". The
template derives this from the entries list (no extra context function).

## Public page (`reading_html/index.html.heex` + `site.css`)

- Pattern-match the feed: `%Entry{}` renders exactly as now; `{:series, ...}`
  renders the approved treatment:
  - small uppercase label (`Series · Author` or series name), styled like a
    muted eyebrow above the group
  - grouped entries indented with a hairline left border
    (`rgba` of the text color, matching the mockup), each keeping its own
    date, "Read/Listened to *Title*" line, and note
- CSS lives in `site.css` beside the existing `.feed-item--book` rules.
- Per-entry anchor ids (slugified title) are preserved inside groups.

## Admin (`Admin.ReadingLive.Index`)

- Drawer gains an optional "Series" text field between Author and Link, with
  `list="series-names"` and a `<datalist id="series-names">` rendered from a
  `@series_names` assign.
- `@series_names` is assigned on mount and refreshed in `refresh_entries/1` so
  a just-saved series suggests immediately.
- The admin entry list itself does not group; it stays a flat editable list.

## Error handling

No new failure modes: `series` is optional, blank normalizes to `nil`, and the
feed function degrades to today's flat list when no entry has a series.

## Testing

Context tests carry the weight (`Newton.ReadingTest`):

- group is positioned at its newest entry; other entries keep chronology
- entries within a group are newest-first; an in-progress entry floats the
  group to the top
- singleton series render as plain entries
- entries without a series pass through in order
- blank series normalizes to nil (changeset)
- `series_names/0` returns distinct sorted names, excluding nil

Web tests (behavior, not markup):

- public page renders a series' entries grouped together
- admin save with a series value persists it
