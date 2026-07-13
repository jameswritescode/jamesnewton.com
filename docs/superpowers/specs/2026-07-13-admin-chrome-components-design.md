# Reusable Admin Chrome Components — Design

**Date:** 2026-07-13
**Status:** Approved direction; not yet implemented

## Problem

The admin's repeated UI chrome is hand-copied across templates. The list
container + row markup is triplicated (posts, reading, photos indexes) with
byte-identical class strings; the page header (`h1` + action button) is
copied across those three plus bare-`h1` variants on the dashboard and
media pages; the lowkey uppercase section heading appears four times across
the media page and the post editor. A visual change means editing N
templates and hoping. AGENTS.md now mandates the fix ("Bias to reusable
components for repeated UI chrome"); this project applies it to the
existing debt.

## Decisions (made during brainstorming)

1. **Scope: both layers plus the mini-pattern.** Extract the page header,
   the list/row pair, and the section heading in one pass.
2. **`/admin/media` adopts `page_header` and `section_header`** only — its
   orphan grid and missing-file list are not row lists and stay bespoke.
3. **Naming:** `list` / `list_item` (the `ul`/`li` mental model), plus
   `page_header` and `section_header`. Components are consumed namespaced
   (`<Components.list>`), so short names don't collide with
   core_components.
4. **API style: slot-based function components** (the house idiom), not
   data-driven column configs (rows are heterogeneous) and not CSS-only
   class extraction (the structural contracts — stream, empty state,
   stretched link — must live in one place too).

## Design

All four components live in `NewtonWeb.Admin.Components` alongside
`button`/`drawer`, consumed as `<Components.*>`.

### `page_header`

- `attr :title, :string, required: true`
- default slot (optional) for actions, rendered right-aligned
- Owns the `mb-6 flex items-center justify-between` row and the
  `h1.text-[1.35rem] font-semibold tracking-tight`.
- Adopters: posts index, reading index, photos index (title + button),
  dashboard and media (title only; the flex/justify wrapper is harmless
  with an empty slot).

### `section_header`

- `attr :title, :string, required: true`
- Owns `mb-3 text-[0.78rem] uppercase tracking-wide text-(--admin-text-subtle)`
  as an `h2`.
- Adopters: media page ("Orphaned files", "Missing files"), post editor
  ("Images"). The editor's Excerpt heading is a `<label for=...>` with the
  same look plus an inline hint — it keeps its bespoke markup (a label is
  not a heading) but this is noted as acceptable divergence.

### `list`

- `attr :id, :string, required: true` — becomes the stream container id
- `attr :empty, :string, required: true` — empty-state text
- default slot: the caller's `:for` rows
- Owns: `overflow-hidden rounded-xl border border-(--admin-border)`,
  `phx-update="stream"` on itself, and the hidden `only:block` empty-state
  div (id `"#{id}-empty"`).

### `list_item`

- `attr :id, :string, required: true` (the stream dom id)
- `attr :navigate, :string, default: nil` / `attr :patch, :string, default: nil`
  (exactly one set by callers; the primary link uses whichever is given)
- slots:
  - `:leading` (optional) — e.g. the gallery thumbnail
  - default slot — the primary link's text (rendered inside the stretched
    link: `after:absolute after:inset-0`)
  - `:inline` (optional) — secondary text beside the link (reading's
    author), rendered in the `min-w-0 flex-1` group with truncation
  - `:meta` (repeatable) — trailing items (badges, dates), rendered in
    order after the flexible region
- Owns the row recipe: `relative flex items-center gap-3 border-b
  border-(--admin-border) bg-(--admin-surface) px-4 py-3 last:border-b-0
  hover:bg-(--admin-accent-soft)`.

### Adoption map

| Page | page_header | section_header | list/list_item |
|---|---|---|---|
| posts index | ✓ (with button) | — | ✓ (+ badge, date meta) |
| reading index | ✓ (with button) | — | ✓ (+ inline author, badge, date) |
| photos index | ✓ (with button) | — | ✓ (+ leading thumb) |
| dashboard | ✓ (title only) | — | — |
| media | ✓ (title only) | ✓ ×2 | — (grid/list stay bespoke) |
| post editor | — | ✓ (Images) | — |

Zero behavior change intended anywhere; the posts index keeps its filter
tabs, reading its summary, etc., between header and list.

## Error handling

None new — these are pure render components. `list_item` with neither
`navigate` nor `patch` renders the text without a link (harmless, unused).

## Testing

- **The refactor's success criterion: every existing admin LiveView test
  passes unchanged.** They assert behaviors (navigation, streams, badges,
  empty states) that must survive markup extraction. Any test edit is a
  red flag to justify.
- Component tests (`Phoenix.LiveViewTest.render_component/2`) in one new
  file: list renders empty-state div wired to the id contract; list_item
  renders navigate vs patch links and all four slot positions;
  page_header with/without action slot; section_header text.
- Visual parity confirmed by James's tophat of the five pages.

## Out of scope

- The media page's orphan card grid and the editor's Images card grid
  (similar to each other; a future `card_grid` if a third appears).
- The editor's Excerpt label (same look, different element semantics).
- Site-side (non-admin) components.
