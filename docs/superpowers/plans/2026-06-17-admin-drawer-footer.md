# Admin Drawer Footer Consistency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Unify all three admin edit drawers around one footer — pinned to the bottom of the drawer with a top divider, laid out `[Delete · spacer · primary]` — and restructure the post Publish drawer to match (publish toggle becomes the footer primary).

**Architecture:** Generalize `drawer_footer/1` into a slotted, bottom-pinned, top-divided footer + add a `save_button/1`; reading/gallery pass `<.save_button/>` in the slot (forms get `flex-1`); the Publish drawer uses the same footer with its publish-toggle buttons in the slot and its body tidied.

**Tech Stack:** Phoenix 1.8 LiveView function components, Tailwind v4.

---

## Context for the implementer

Read the spec first: `docs/superpowers/specs/2026-06-17-admin-drawer-footer-design.md`.

**Current code (exact):**
- `Components.drawer/1` panel is `fixed … flex w-80 max-w-[calc(100vw-3rem)] flex-col gap-4 overflow-y-auto … bg-(--admin-sidebar) p-5 …`, then a header row (title + close X) and `{render_slot(@inner_block)}`. The footer is rendered inside `inner_block`.
- `Components.drawer_footer/1` (current): attrs `cancel_path` (required), `deletable?`, `delete_event`, `delete_id`, `delete_confirm`, `save_label`. Renders `<div class="mt-2 flex items-center gap-2">` → optional `delete_button`, `flex-1` spacer, a Cancel `<.link patch={@cancel_path}>`, and a `type="submit"` Save (`{@save_label}`).
- `Components.delete_button/1`: `event`/`id`/`confirm`/`label` — keep as-is.
- **Reading** `reading_drawer/1` (`reading_live/index.ex`): `<.form for={@form} id="reading-form" … class="flex flex-col gap-3">` … fields … `<Components.drawer_footer cancel_path={~p"/admin/reading"} deletable?={@entry.id != nil} delete_event="delete" delete_id={@entry.id} delete_confirm="Delete this entry?" />` then `</.form>`.
- **Gallery** `settings_drawer/1` (`gallery_live/components.ex`): `<.form for={@form} id="gallery-form" … class="flex flex-col gap-3">` … fields … `<Components.drawer_footer cancel_path={@cancel_path} deletable?={@editing?} delete_event="delete_gallery" delete_confirm="Delete this gallery and all its photos?" />` then `</.form>`.
- **Publish drawer** (`post_live/editor.ex`, inside `<Components.drawer :if={@drawer_open} id="publish-drawer" on_close="close_drawer">`): a Status `<div>`, the `#publish-date-form` (shown `:if={@published_at}`), a `<div class="flex gap-2">` with full-width **Publish now** (`phx-click="publish_now"`, `:if status != :published`) and **Move to draft** (`phx-click="unpublish"`, `:if status != :draft`), a Reading time `<div>`, a View-on-site `<.link>`, a `<div class="flex-1"></div>`, and a standalone `<Components.delete_button :if={@post.id} event="delete" confirm="Delete this post permanently?" />`.

**Existing tests that exercise these (must stay green):**
- `reading_live_test.exs`: `#reading-drawer button` "Delete" deletes + redirects; form submit saves.
- `gallery_show_live_test.exs`: `#gallery-drawer button` "Delete" deletes.
- `post_editor_live_test.exs`: `#publish-drawer button` "Publish now" / "Move to draft" / "Delete" behaviors. These labels/events are all preserved by this change.
- `components_test.exs`: currently tests the old `drawer_footer` API — rewritten in Task 1.

**Rules:** TDD. Test behaviors, not CSS classes. `mix precommit` at the end. For my own test server use `PORT=4001` (never touch 4000). Commits use the `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` trailer (signing is on; retry on a 1Password `failed to fill whole buffer`).

## File structure

| File | Responsibility | Action |
| --- | --- | --- |
| `lib/newton_web/components/admin/components.ex` | slotted `drawer_footer/1` + `save_button/1` | Modify |
| `test/newton_web/components/admin/components_test.exs` | component tests | Modify |
| `lib/newton_web/live/admin/reading_live/index.ex` | footer slot + form `flex-1` | Modify |
| `lib/newton_web/live/admin/gallery_live/components.ex` | footer slot + form `flex-1` | Modify |
| `lib/newton_web/live/admin/post_live/editor.ex` | publish drawer restructure | Modify |

---

## Task 1: Slotted, pinned `drawer_footer/1` + `save_button/1`

**Files:**
- Modify: `lib/newton_web/components/admin/components.ex`
- Test: `test/newton_web/components/admin/components_test.exs`

- [ ] **Step 1: Rewrite the component tests (failing)**

Replace the whole body of `test/newton_web/components/admin/components_test.exs` with:

```elixir
defmodule NewtonWeb.Admin.ComponentsTest do
  use NewtonWeb.ConnCase, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest
  alias NewtonWeb.Admin.Components

  test "drawer_footer renders the slot primary, a Cancel link, and Delete when deletable" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Components.drawer_footer
        cancel_path="/admin/reading"
        deletable?={true}
        delete_event="delete"
        delete_id={7}
        delete_confirm="Delete this entry?"
      >
        PRIMARY-SLOT
      </Components.drawer_footer>
      """)

    assert html =~ "PRIMARY-SLOT"
    assert html =~ "Cancel"
    assert html =~ "Delete"
    assert html =~ ~s(data-confirm="Delete this entry?")
    assert html =~ ~s(phx-value-id="7")
  end

  test "drawer_footer omits Delete and Cancel when not configured" do
    assigns = %{}

    html =
      rendered_to_string(~H"""
      <Components.drawer_footer deletable?={false}>
        PRIMARY-SLOT
      </Components.drawer_footer>
      """)

    assert html =~ "PRIMARY-SLOT"
    refute html =~ "Delete"
    refute html =~ "Cancel"
  end

  test "save_button renders a submit labeled Save" do
    html = render_component(&Components.save_button/1, %{})
    assert html =~ ~s(type="submit")
    assert html =~ "Save"
  end

  test "delete_button omits phx-value-id when no id is given" do
    html =
      render_component(&Components.delete_button/1, event: "delete_gallery", confirm: "Delete it?")

    assert html =~ ~s(phx-click="delete_gallery")
    assert html =~ ~s(data-confirm="Delete it?")
    refute html =~ "phx-value-id"
  end
end
```

- [ ] **Step 2: Run them to verify they fail**

Run: `mix test test/newton_web/components/admin/components_test.exs`
Expected: FAIL — `save_button/1` undefined; `drawer_footer` requires `cancel_path` and has no slot, so the new calls don't compile/match.

- [ ] **Step 3: Rewrite `drawer_footer/1` and add `save_button/1`**

In `lib/newton_web/components/admin/components.ex`, replace the current `drawer_footer/1` (its `@doc`, `attr`s, and function) with:

```elixir
  @doc """
  The shared edit-drawer footer: pinned to the bottom of the drawer with a top
  divider (full-bleed via `-mx-5` to cancel the drawer's padding). An optional
  Delete on the left, a spacer, an optional Cancel link, then the caller's primary
  action(s) in the slot (a `save_button`, or the post publish toggles).
  """
  attr :cancel_path, :string, default: nil
  attr :deletable?, :boolean, default: false
  attr :delete_event, :string, default: nil
  attr :delete_id, :any, default: nil
  attr :delete_confirm, :string, default: nil
  slot :inner_block, required: true

  def drawer_footer(assigns) do
    ~H"""
    <div class="mt-auto -mx-5 flex items-center gap-2 border-t border-(--admin-border) px-5 pt-4">
      <.delete_button
        :if={@deletable?}
        event={@delete_event}
        id={@delete_id}
        confirm={@delete_confirm}
      />
      <div class="flex-1"></div>
      <.link
        :if={@cancel_path}
        patch={@cancel_path}
        class="rounded-md px-3 py-1.5 text-[0.78rem] text-(--admin-text-muted) no-underline hover:text-(--admin-text)"
      >
        Cancel
      </.link>
      {render_slot(@inner_block)}
    </div>
    """
  end

  @doc "The primary submit button used in edit-drawer footers."
  attr :label, :string, default: "Save"

  def save_button(assigns) do
    ~H"""
    <button
      type="submit"
      class="rounded-md bg-(--admin-accent) px-3 py-1.5 text-[0.78rem] font-medium text-white hover:bg-(--admin-accent-hover)"
    >
      {@label}
    </button>
    """
  end
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/newton_web/components/admin/components_test.exs`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/newton_web/components/admin/components.ex test/newton_web/components/admin/components_test.exs
git commit -m "Make drawer_footer a slotted, bottom-pinned footer with a divider

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Reading & Gallery adopt the slotted footer

**Files:**
- Modify: `lib/newton_web/live/admin/reading_live/index.ex`, `lib/newton_web/live/admin/gallery_live/components.ex`

- [ ] **Step 1: Reading — form `flex-1` + Save in the slot**

In `reading_live/index.ex` `reading_drawer/1`:
- Change the form class from `class="flex flex-col gap-3"` to `class="flex flex-1 flex-col gap-3"`.
- Change the self-closing footer to a slotted one:

```heex
        <Components.drawer_footer
          cancel_path={~p"/admin/reading"}
          deletable?={@entry.id != nil}
          delete_event="delete"
          delete_id={@entry.id}
          delete_confirm="Delete this entry?"
        >
          <Components.save_button />
        </Components.drawer_footer>
```

- [ ] **Step 2: Gallery — form `flex-1` + Save in the slot**

In `gallery_live/components.ex` `settings_drawer/1`:
- Change the form class from `class="flex flex-col gap-3"` to `class="flex flex-1 flex-col gap-3"`.
- Change the footer to:

```heex
        <Components.drawer_footer
          cancel_path={@cancel_path}
          deletable?={@editing?}
          delete_event="delete_gallery"
          delete_confirm="Delete this gallery and all its photos?"
        >
          <Components.save_button />
        </Components.drawer_footer>
```

- [ ] **Step 3: Compile + run the reading/gallery suites**

Run: `mix compile --warnings-as-errors 2>&1 | tail -3` then `mix test test/newton_web/live/admin/reading_live_test.exs test/newton_web/live/admin/gallery_show_live_test.exs test/newton_web/live/admin/gallery_index_live_test.exs`
Expected: clean compile; all pass (Delete/Save/Cancel labels + events unchanged; the footer is just relocated/restyled).

- [ ] **Step 4: Commit**

```bash
git add lib/newton_web/live/admin/reading_live/index.ex lib/newton_web/live/admin/gallery_live/components.ex
git commit -m "Pin reading and gallery drawer footers to the bottom

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Restructure the Publish drawer (Option 1)

**Files:**
- Modify: `lib/newton_web/live/admin/post_live/editor.ex`

- [ ] **Step 1: Replace the publish-drawer body below the date form**

In `post_live/editor.ex`, inside the `<Components.drawer id="publish-drawer" …>`, the markup currently is: the Status `<div>`, the `#publish-date-form`, then a `<div class="flex gap-2">` (Publish now / Move to draft), a Reading-time `<div>`, a View-on-site `<.link>`, a `<div class="flex-1"></div>`, and a `<Components.delete_button …/>`.

Replace **everything from the `<div class="flex gap-2">` through the closing `</Components.delete_button>`-equivalent** (i.e. the publish-buttons row, reading-time, view-on-site, the flex-1 spacer, and the standalone delete_button) with a tidy meta line + the shared footer:

```heex
        <div class="text-[0.78rem] text-(--admin-text-subtle)">
          Reading time · {@post.reading_time || "—"} min
          <.link
            :if={@post.id}
            href={~p"/posts/#{@post.slug}"}
            target="_blank"
            class="ml-2 text-(--admin-accent) no-underline hover:underline"
          >
            View on site ↗
          </.link>
        </div>

        <Components.drawer_footer
          deletable?={@post.id != nil}
          delete_event="delete"
          delete_confirm="Delete this post permanently?"
        >
          <button
            :if={Blog.publish_status(@published_at) != :published}
            type="button"
            phx-click="publish_now"
            class="rounded-md bg-(--admin-accent) px-3 py-1.5 text-[0.78rem] font-medium text-white hover:bg-(--admin-accent-hover)"
          >
            Publish now
          </button>
          <button
            :if={Blog.publish_status(@published_at) != :draft}
            type="button"
            phx-click="unpublish"
            class="rounded-md border border-(--admin-border) px-3 py-1.5 text-[0.78rem] hover:bg-(--admin-accent-soft)"
          >
            Move to draft
          </button>
        </Components.drawer_footer>
```

Leave the Status `<div>` and the `#publish-date-form` above this untouched. (The publish buttons lose their `flex-1` full-width class — they now size to content on the footer's right.)

- [ ] **Step 2: Compile + run the editor suite**

Run: `mix compile --warnings-as-errors 2>&1 | tail -3` then `mix test test/newton_web/live/admin/post_editor_live_test.exs`
Expected: clean compile; all pass — `#publish-drawer button` "Publish now" / "Move to draft" / "Delete" and the publish-date / delete-redirect tests are unchanged (buttons relocated into the footer, same labels/events).

- [ ] **Step 3: Commit**

```bash
git add lib/newton_web/live/admin/post_live/editor.ex
git commit -m "Restructure the publish drawer onto the shared footer grammar

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Verification

**Files:** none (verification only)

- [ ] **Step 1: Full suite**

Run: `mix precommit`
Expected: PASS — compile `--warnings-as-errors`, format, Credo, all tests (incl. the rewritten component tests), Dialyzer 0.

- [ ] **Step 2: Build assets + browser screenshot pass (test server on PORT=4001)**

Run `mix assets.build`. Start `PORT=4001 mix phx.server` (do **not** kill or use 4000). Log in (your local admin credentials). Using Playwright against `http://localhost:4001`, screenshot:
- the **reading** edit drawer (existing entry), the **gallery settings** drawer, and the **publish** drawer in both a **draft** post and a **published** post.

Confirm in each: the footer is pinned to the bottom of the drawer with a top divider; layout is `[Delete · … · primary]`; reading/gallery primary is Save (+ Cancel); publish primary is "Publish now" (draft) / "Move to draft" (published). No horizontal overflow.
Stop the PORT=4001 server when done (kill only 4001).

- [ ] **Step 3: Report**

Summarize the four drawers (reading, gallery, publish-draft, publish-published) with the screenshots. Fix and re-verify anything that doesn't match mockup v3 before declaring done.

---

## Self-review notes

- **Spec coverage:** §1 slotted/pinned/divided `drawer_footer` + `save_button` → Task 1; §2 reading/photos adopt (slot + `flex-1`) → Task 2; §3 publish drawer restructure (Option 1, body tidy + footer with publish toggles) → Task 3; testing → Task 1 component tests, Tasks 2–3 LiveView suites, Task 4 precommit + screenshots.
- **Name/type consistency:** `drawer_footer/1` (new attrs `cancel_path` optional, `deletable?`, `delete_event`, `delete_id`, `delete_confirm`, `slot inner_block`) and `save_button/1` are defined in Task 1 and called exactly that way in Tasks 2–3. `delete_button/1` unchanged. The footer container classes (`mt-auto -mx-5 … border-t … px-5 pt-4`) appear once (in the component); callers only supply the slot.
- **Layout mechanism:** the nested form drawers (reading/gallery) need `flex-1` so the footer's `mt-auto` reaches the drawer bottom (Task 2); the publish drawer's footer is a direct child of the flex-col panel, so `mt-auto` works without a wrapper (Task 3). `-mx-5` makes the divider full-bleed against the drawer's `p-5`.
- **No placeholders:** all code/commands concrete; the publish-drawer replacement names exactly which existing block to remove.
- **Out of scope:** post-editor restructuring beyond the drawer; sticky-on-scroll footer; per-photo controls; header dividers.
