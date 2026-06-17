# Admin Drawer Footer Consistency — Design Spec

**Date:** 2026-06-17
**Status:** Approved (pending written review)
**Branch context:** `phoenix-migration`

## Overview

A follow-up to the control-consistency pass that addresses the real design drift
the user flagged: the post **Publish** drawer is a stack of full-width controls,
while the reading/photos drawers are compact forms. This unifies all three admin
edit drawers around one **footer grammar** — a footer pinned to the bottom of the
drawer with a top divider, laid out as **`[Delete · spacer · primary action]`**.
Posts stays a full-page editor with its settings drawer; only the drawer chrome
and controls converge (Approach A: shared design language, keep each structure).

Validated visually via the brainstorming companion (mockup v3).

## Decisions (locked)

- **Approach A** — shared design language across Posts/Reading/Photos; do **not**
  restructure posts into a drawer-as-form.
- **Footer grammar** in every edit drawer: bottom-pinned, a **top border**
  dividing it from the body, `Delete` (left) · spacer · **primary** (right).
- **Publish drawer (Option 1):** the publish toggle becomes the footer's primary —
  **Publish now** (solid-accent, like Save) for a draft, **Move to draft**
  (bordered/secondary) for a published post; a **scheduled** post shows both. No
  Save/Cancel (publish applies on click). `Delete` on the left.
- Reading/Photos keep `Delete · Cancel · Save`, now in the same pinned/divided
  footer.

## Current state (reference)

- `Components.drawer/1` panel: `fixed … flex w-80 … flex-col gap-4 overflow-y-auto
  … p-5`, with a header row (title + close X, **no** border) then `inner_block`.
- `Components.drawer_footer/1` (from the prior pass): `<div class="mt-2 flex
  items-center gap-2">` with optional `delete_button`, a `flex-1` spacer, a Cancel
  `<.link patch={@cancel_path}>`, and a `type="submit"` Save. Used by reading
  (`reading_drawer/1`) and gallery (`settings_drawer/1`).
- Post editor publish drawer: status text, the publish-date form, full-width
  **Publish now / Move to draft** buttons, reading time, View on site, a `flex-1`
  spacer, then a standalone `<.delete_button>` — all full-width-stacked.

## Section 1 — `drawer_footer/1` becomes the shared, slotted footer

Generalize `drawer_footer/1` so all three drawers use it:

```elixir
attr :cancel_path, :string, default: nil      # renders a Cancel link when set
attr :deletable?, :boolean, default: false
attr :delete_event, :string, default: nil
attr :delete_id, :any, default: nil
attr :delete_confirm, :string, default: nil
slot :inner_block, required: true             # the right-side primary action(s)
```

Renders the **bottom-pinned, top-divided** container:

```heex
<div class="mt-auto -mx-5 flex items-center gap-2 border-t border-(--admin-border) px-5 pt-4">
  <.delete_button :if={@deletable?} event={@delete_event} id={@delete_id} confirm={@delete_confirm} />
  <div class="flex-1"></div>
  <.link :if={@cancel_path} patch={@cancel_path} class="rounded-md px-3 py-1.5 text-[0.78rem] text-(--admin-text-muted) no-underline hover:text-(--admin-text)">
    Cancel
  </.link>
  {render_slot(@inner_block)}
</div>
```

- **`mt-auto`** pins the footer to the bottom of the drawer's flex column (the
  panel is `flex flex-col` and full-height via `inset-y-0`).
- **`-mx-5 … px-5`** cancels the drawer's `p-5` so the **top border spans the full
  drawer width** (full-bleed, like a header divider), while the buttons keep their
  inset padding.
- The right-side primary moves to a **slot** so each drawer supplies its own
  (Save for forms; publish toggles for posts).

Add a small **`save_button/1`** (the accent submit) so the two form drawers don't
duplicate the Save markup:

```elixir
attr :label, :string, default: "Save"
def save_button(assigns) do
  ~H"""
  <button type="submit" class="rounded-md bg-(--admin-accent) px-3 py-1.5 text-[0.78rem] font-medium text-white hover:bg-(--admin-accent-hover)">
    {@label}
  </button>
  """
end
```

## Section 2 — Reading & Photos adopt the slotted footer

Both already call `drawer_footer`; update the calls to pass the Save in the slot,
and let the footer pin to the bottom:

- **Reading** (`reading_drawer/1`): the `<.form id="reading-form" class="flex
  flex-col gap-3">` gains `flex-1` (`class="flex flex-1 flex-col gap-3"`) so its
  last child (`drawer_footer`) can `mt-auto` to the drawer bottom. The call:
  ```heex
  <.drawer_footer
    cancel_path={~p"/admin/reading"}
    deletable?={@entry.id != nil}
    delete_event="delete"
    delete_id={@entry.id}
    delete_confirm="Delete this entry?"
  >
    <.save_button />
  </.drawer_footer>
  ```
- **Gallery** (`settings_drawer/1`): the gallery `<.form>` gains `flex-1` likewise,
  and:
  ```heex
  <.drawer_footer
    cancel_path={@cancel_path}
    deletable?={@editing?}
    delete_event="delete_gallery"
    delete_confirm="Delete this gallery and all its photos?"
  >
    <.save_button />
  </.drawer_footer>
  ```

## Section 3 — Publish drawer restructure (Option 1)

In `PostLive.Editor`'s publish drawer:

- **Body** (above the footer): keep Status and the publish-date form as labeled
  sections, and collapse Reading time + View on site into one quiet meta line.
  Remove the in-body full-width **Publish now / Move to draft** buttons and the
  in-body `flex-1` spacer and standalone Delete.
- **Footer:** a `drawer_footer` with `deletable?` = `@post.id != nil`,
  `delete_event="delete"`, `delete_confirm="Delete this post permanently?"`, **no**
  `cancel_path`, and the publish toggle button(s) in the slot:
  ```heex
  <.drawer_footer deletable?={@post.id != nil} delete_event="delete" delete_confirm="Delete this post permanently?">
    <button :if={Blog.publish_status(@published_at) != :published} type="button" phx-click="publish_now"
      class="rounded-md bg-(--admin-accent) px-3 py-1.5 text-[0.78rem] font-medium text-white hover:bg-(--admin-accent-hover)">
      Publish now
    </button>
    <button :if={Blog.publish_status(@published_at) != :draft} type="button" phx-click="unpublish"
      class="rounded-md border border-(--admin-border) px-3 py-1.5 text-[0.78rem] hover:bg-(--admin-accent-soft)">
      Move to draft
    </button>
  </.drawer_footer>
  ```
  - Draft → only **Publish now** (accent). Published → only **Move to draft**
    (bordered). Scheduled (future date) → **both** on the right.
  - `Components.delete_button` is no longer used standalone in this drawer (the
    footer renders Delete).

The publish-date form (`#publish-date-form`) stays in the body, only shown when
`@published_at` is set, using the existing date input styling.

## Error handling / edge cases

- **Scheduled posts** show two right-side buttons; the footer's `gap-2` handles
  spacing (matches reading's Cancel+Save spacing).
- **New post (`@post.id` nil):** no Delete; footer is `[spacer · Publish now]`.
- **Drawer scroll:** with `overflow-y-auto`, a tall body scrolls; `mt-auto` keeps
  the footer at the bottom when the body is short (not a sticky overlay — adequate
  for these short drawers).
- **Form submit:** the Save stays inside each form (in the slot), so submit still
  works; the publish toggles are `phx-click` buttons, unaffected by being in the
  footer.

## Testing approach

Behaviors, not structure.

- **Reading/Photos:** existing drawer tests (delete, save, cancel) still pass —
  selectors target `#reading-drawer button`/`#gallery-drawer button` "Delete"/
  "Save" which are unchanged.
- **Publish drawer:** existing editor tests targeting `#publish-drawer button`
  "Publish now" / "Move to draft" / "Delete" still pass (the buttons moved into the
  footer but keep their labels and events). The publish-date and
  publish/unpublish/delete behaviors are unchanged.
- **Visual:** a screenshot pass of all three drawers (reading, gallery settings,
  publish in draft + published) confirms the pinned, divided footer and the
  `[Delete · … · primary]` layout.

## Unit breakdown

- `NewtonWeb.Admin.Components` — `drawer_footer/1` (slotted, pinned, divided) and
  new `save_button/1`.
- `reading_live/index.ex` (`reading_drawer/1`) — form `flex-1`; footer slot.
- `gallery_live/components.ex` (`settings_drawer/1`) — form `flex-1`; footer slot.
- `post_live/editor.ex` — publish drawer body tidy + `drawer_footer` with publish
  toggles in the slot.

## Out of scope

- Restructuring the post editor into a drawer-as-form (Approach B/C, rejected).
- A sticky (overlay) footer on scroll — `mt-auto` bottom-pin is sufficient.
- The per-photo drawer / photo grid controls (separate context).
- Header dividers on drawers (the user asked only for the footer border).
