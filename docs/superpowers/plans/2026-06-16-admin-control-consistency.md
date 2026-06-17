# Admin Control Consistency Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make admin edit-drawer controls and list tables consistent — shared Delete/Cancel/Save components, a global button pointer cursor, and removal of the lone posts-table delete.

**Architecture:** Extract `delete_button/1` and `drawer_footer/1` into `NewtonWeb.Admin.Components`; reading + gallery drawers adopt `drawer_footer`, the post editor's publish drawer adopts `delete_button` (relabeled "Delete"). Add one scoped CSS rule for the button cursor. Remove the posts list row delete + its handler.

**Tech Stack:** Phoenix 1.8 LiveView function components, Tailwind v4, esbuild.

---

## Context for the implementer

Read the spec first: `docs/superpowers/specs/2026-06-16-admin-control-consistency-design.md`.

**Current markup (exact):**
- `NewtonWeb.Admin.Components` (`lib/newton_web/components/admin/components.ex`) has `drawer/1` and `field/1`, ending with a private `field_class/0`. It is `use NewtonWeb, :html` and already aliased as `Components` in the reading, gallery, and editor modules.
- **Reading footer** (`lib/newton_web/live/admin/reading_live/index.ex`, `reading_drawer/1`): a `<div class="mt-2 flex items-center gap-2">` with Delete (`phx-click="delete" phx-value-id={@entry.id}` confirm "Delete this entry?", shown `:if={@entry.id}`), a `flex-1` spacer, Cancel `<.link patch={~p"/admin/reading"}>`, and a `type="submit"` Save.
- **Gallery footer** (`lib/newton_web/live/admin/gallery_live/components.ex`, `settings_drawer/1`, drawer id `gallery-drawer`): the same row with Delete (`phx-click="delete_gallery"` no id, confirm "Delete this gallery and all its photos?", `:if={@editing?}`), Cancel `<.link patch={@cancel_path}>`, Save submit.
- **Post editor** (`lib/newton_web/live/admin/post_live/editor.ex`): publish drawer (id `publish-drawer`) ends with a standalone `<button :if={@post.id} type="button" phx-click="delete" data-confirm="Delete this post permanently?" class="rounded-md border border-(--admin-border) px-3 py-1.5 text-[0.8rem] text-(--admin-accent) hover:bg-(--admin-accent-soft)">Delete post</button>`.
- **Posts list** (`lib/newton_web/live/admin/post_live/index.ex`): the post row ends with a `<button type="button" phx-click="delete" phx-value-id={post.id} data-confirm="Delete this post?" class="relative z-10 ...">Delete</button>`; there is a matching `handle_event("delete", %{"id" => id}, socket)` clause.

**Shared styling strings (use verbatim):**
- Delete: `rounded-md border border-(--admin-border) px-3 py-1.5 text-[0.78rem] text-(--admin-accent) hover:bg-(--admin-accent-soft)`
- Cancel link: `rounded-md px-3 py-1.5 text-[0.78rem] text-(--admin-text-muted) no-underline hover:text-(--admin-text)`
- Save submit: `rounded-md bg-(--admin-accent) px-3 py-1.5 text-[0.78rem] font-medium text-white hover:bg-(--admin-accent-hover)`

**Test selectors that depend on labels:** the post editor delete test
(`test/newton_web/live/admin/post_editor_live_test.exs:300`) targets
`element("#publish-drawer button", "Delete post")` — must change to `"Delete"`.
Reading (`#reading-drawer button` "Delete") and gallery (`#gallery-drawer button`
"Delete") already use "Delete" and stay valid.

**Rules:** TDD where it fits (component render tests; the CSS rule is verified by
build + the final browser pass). Test behaviors, not CSS-class snapshots. `mix
precommit` at the end. Commits use the `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` trailer; signing is back (use a normal `git commit`); if the 1Password agent errors with `failed to fill whole buffer`, retry the same command up to ~4 times.

## File structure

| File | Responsibility | Action |
| --- | --- | --- |
| `lib/newton_web/components/admin/components.ex` | `delete_button/1`, `drawer_footer/1` | Modify |
| `test/newton_web/components/admin/components_test.exs` | component render tests | Create |
| `lib/newton_web/live/admin/reading_live/index.ex` | adopt `drawer_footer` | Modify |
| `lib/newton_web/live/admin/gallery_live/components.ex` | adopt `drawer_footer` | Modify |
| `lib/newton_web/live/admin/post_live/editor.ex` | adopt `delete_button` | Modify |
| `test/newton_web/live/admin/post_editor_live_test.exs` | relabel selector | Modify |
| `lib/newton_web/live/admin/post_live/index.ex` | remove row delete + handler | Modify |
| `test/newton_web/live/admin/post_index_live_test.exs` | remove list-delete test | Modify |
| `assets/css/admin.css` | global button cursor rule | Modify |

---

## Task 1: Shared `delete_button/1` and `drawer_footer/1` components

**Files:**
- Modify: `lib/newton_web/components/admin/components.ex`
- Test: `test/newton_web/components/admin/components_test.exs`

- [ ] **Step 1: Write the failing tests**

Create `test/newton_web/components/admin/components_test.exs`:

```elixir
defmodule NewtonWeb.Admin.ComponentsTest do
  use NewtonWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  alias NewtonWeb.Admin.Components

  test "drawer_footer renders Cancel and Save, and Delete when deletable" do
    html =
      render_component(&Components.drawer_footer/1,
        cancel_path: "/admin/reading",
        deletable?: true,
        delete_event: "delete",
        delete_id: 7,
        delete_confirm: "Delete this entry?"
      )

    assert html =~ "Cancel"
    assert html =~ "Save"
    assert html =~ "Delete"
    assert html =~ ~s(data-confirm="Delete this entry?")
    assert html =~ ~s(phx-value-id="7")
  end

  test "drawer_footer omits Delete when not deletable" do
    html =
      render_component(&Components.drawer_footer/1, cancel_path: "/admin/reading", deletable?: false)

    assert html =~ "Save"
    assert html =~ "Cancel"
    refute html =~ "Delete"
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
Expected: FAIL — `Components.drawer_footer/1` / `delete_button/1` undefined.

- [ ] **Step 3: Implement the components**

In `lib/newton_web/components/admin/components.ex`, add these two public components
immediately above `defp field_class do`:

```elixir
  @doc "Consistent destructive button used in admin edit drawers."
  attr :event, :string, required: true
  attr :id, :any, default: nil
  attr :confirm, :string, required: true
  attr :label, :string, default: "Delete"

  def delete_button(assigns) do
    ~H"""
    <button
      type="button"
      phx-click={@event}
      phx-value-id={@id}
      data-confirm={@confirm}
      class="rounded-md border border-(--admin-border) px-3 py-1.5 text-[0.78rem] text-(--admin-accent) hover:bg-(--admin-accent-soft)"
    >
      {@label}
    </button>
    """
  end

  @doc """
  The shared edit-drawer action row: an optional Delete on the left, then Cancel
  and a submit Save on the right. Render inside the drawer's `<.form>`.
  """
  attr :cancel_path, :string, required: true
  attr :deletable?, :boolean, default: false
  attr :delete_event, :string, default: nil
  attr :delete_id, :any, default: nil
  attr :delete_confirm, :string, default: nil
  attr :save_label, :string, default: "Save"

  def drawer_footer(assigns) do
    ~H"""
    <div class="mt-2 flex items-center gap-2">
      <.delete_button
        :if={@deletable?}
        event={@delete_event}
        id={@delete_id}
        confirm={@delete_confirm}
      />
      <div class="flex-1"></div>
      <.link
        patch={@cancel_path}
        class="rounded-md px-3 py-1.5 text-[0.78rem] text-(--admin-text-muted) no-underline hover:text-(--admin-text)"
      >
        Cancel
      </.link>
      <button
        type="submit"
        class="rounded-md bg-(--admin-accent) px-3 py-1.5 text-[0.78rem] font-medium text-white hover:bg-(--admin-accent-hover)"
      >
        {@save_label}
      </button>
    </div>
    """
  end
```

Also update the module's `@moduledoc` to mention the new components (append:
" plus a `delete_button/1` and a `drawer_footer/1` action row.").

- [ ] **Step 4: Run the tests to verify they pass**

Run: `mix test test/newton_web/components/admin/components_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/newton_web/components/admin/components.ex test/newton_web/components/admin/components_test.exs
git commit -m "Add shared delete_button and drawer_footer admin components

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: Adopt the shared controls in the three editors

**Files:**
- Modify: `lib/newton_web/live/admin/reading_live/index.ex`, `lib/newton_web/live/admin/gallery_live/components.ex`, `lib/newton_web/live/admin/post_live/editor.ex`
- Test: `test/newton_web/live/admin/post_editor_live_test.exs`

- [ ] **Step 1: Relabel the post editor delete test selector (will fail until Step 4)**

In `test/newton_web/live/admin/post_editor_live_test.exs`, change the delete test's
selector from `"Delete post"` to `"Delete"`:

```elixir
    |> element("#publish-drawer button", "Delete")
```

- [ ] **Step 2: Run the editor test to verify it fails**

Run: `mix test test/newton_web/live/admin/post_editor_live_test.exs:293`
Expected: FAIL — the button still reads "Delete post".

- [ ] **Step 3: Reading drawer adopts `drawer_footer`**

In `lib/newton_web/live/admin/reading_live/index.ex` `reading_drawer/1`, replace the
entire footer `<div class="mt-2 flex items-center gap-2"> … </div>` (the Delete +
Cancel + Save block) with:

```heex
        <.drawer_footer
          cancel_path={~p"/admin/reading"}
          deletable?={@entry.id != nil}
          delete_event="delete"
          delete_id={@entry.id}
          delete_confirm="Delete this entry?"
        />
```

- [ ] **Step 4: Gallery settings drawer adopts `drawer_footer`**

In `lib/newton_web/live/admin/gallery_live/components.ex` `settings_drawer/1`, replace
its footer `<div class="mt-2 flex items-center gap-2"> … </div>` with:

```heex
        <.drawer_footer
          cancel_path={@cancel_path}
          deletable?={@editing?}
          delete_event="delete_gallery"
          delete_confirm="Delete this gallery and all its photos?"
        />
```

- [ ] **Step 5: Post editor publish drawer adopts `delete_button`**

In `lib/newton_web/live/admin/post_live/editor.ex`, replace the standalone
`<button … >Delete post</button>` (the `phx-click="delete"` one in the publish
drawer) with:

```heex
        <.delete_button
          :if={@post.id}
          event="delete"
          confirm="Delete this post permanently?"
        />
```

(`Components` is aliased here; if the editor calls components as `Components.drawer`,
use `<Components.delete_button …>` — match the existing call style in each file.
Check: reading/gallery already call `<Components.drawer>`/`<Components.field>`, so
use `<Components.drawer_footer …>` / `<Components.delete_button …>` accordingly.)

- [ ] **Step 6: Run the affected suites**

Run: `mix test test/newton_web/live/admin/`
Expected: PASS — reading delete/save/cancel, gallery settings delete/save, and the
post editor delete-and-redirect tests all green with the shared controls. Clean
compile (`mix compile --warnings-as-errors 2>&1 | tail -3`).

- [ ] **Step 7: Commit**

```bash
git add lib/newton_web/live/admin/reading_live/index.ex lib/newton_web/live/admin/gallery_live/components.ex lib/newton_web/live/admin/post_live/editor.ex test/newton_web/live/admin/post_editor_live_test.exs
git commit -m "Use shared drawer_footer/delete_button across admin editors

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Remove the posts table delete

**Files:**
- Modify: `lib/newton_web/live/admin/post_live/index.ex`, `test/newton_web/live/admin/post_index_live_test.exs`

- [ ] **Step 1: Remove the list-delete test**

In `test/newton_web/live/admin/post_index_live_test.exs`, delete the whole test
`"deletes a post from the list"` (it asserts the row Delete behavior we're removing).

- [ ] **Step 2: Remove the row delete button and handler**

In `lib/newton_web/live/admin/post_live/index.ex`:
- Delete the post-row `<button type="button" phx-click="delete" phx-value-id={post.id} data-confirm="Delete this post?" class="relative z-10 …">Delete</button>` block.
- Delete the `handle_event("delete", %{"id" => id}, socket)` clause (the row's
  handler — now unused).

- [ ] **Step 3: Compile + run the posts index tests**

Run: `mix compile --warnings-as-errors 2>&1 | tail -3` then `mix test test/newton_web/live/admin/post_index_live_test.exs`
Expected: clean compile (no "unused" warnings for a leftover handler); the index
tests pass (filter/new-post/list tests unaffected; the delete test is gone).

- [ ] **Step 4: Confirm no stale references**

Run: `grep -n "phx-click=\"delete\"" lib/newton_web/live/admin/post_live/index.ex`
Expected: no matches (the row delete is gone; the editor's delete lives in
`editor.ex`, not here).

- [ ] **Step 5: Commit**

```bash
git add lib/newton_web/live/admin/post_live/index.ex test/newton_web/live/admin/post_index_live_test.exs
git commit -m "Remove the row delete from the posts list

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 4: Global admin button cursor

**Files:**
- Modify: `assets/css/admin.css`

- [ ] **Step 1: Add the rule**

Append to `assets/css/admin.css`:

```css
/* Admin buttons get a pointer cursor (Tailwind v4 defaults buttons to
   cursor:default). Scoped to the admin (data-admin-theme is only set on the
   admin <html>) and kept at zero specificity so cursor-* utilities still win;
   :not(:disabled) leaves the editor's disabled "Saving…" button alone. */
:where([data-admin-theme]) button:not(:disabled) {
  cursor: pointer;
}
```

- [ ] **Step 2: Build and confirm the rule is bundled**

Run: `mix assets.build` then `grep -c "data-admin-theme.*cursor\|cursor: pointer" priv/static/assets/css/app.css`
Expected: build succeeds; grep returns ≥ 1 (the rule made it into the bundle).
(The visual confirmation happens in Task 5.)

- [ ] **Step 3: Commit**

```bash
git add assets/css/admin.css
git commit -m "Give admin buttons a pointer cursor via one scoped rule

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 5: Verification

**Files:** none (verification only)

- [ ] **Step 1: Full suite**

Run: `mix precommit`
Expected: PASS — compile `--warnings-as-errors`, format, Credo, all tests
(including the new component tests), Dialyzer 0.

- [ ] **Step 2: Browser pass (start one dev server; stop it after)**

Start `mix phx.server`, log in (`hello@jamesnewton.com` / `password1234`). Using
Playwright (the `assets/screenshot.mjs` pattern):
- Hover a Save/Delete button in an admin drawer and confirm `getComputedStyle(btn).cursor === "pointer"`; confirm a disabled state (open a draft editor, type → the "Saving…" button) reports `cursor` not `pointer`.
- Open the reading edit drawer, the gallery settings drawer, and the post editor's
  publish drawer; confirm each shows a "Delete" button with consistent styling, a
  "Cancel" (reading/gallery) and "Save".
- Confirm the posts list rows no longer render a Delete button, and the row still
  navigates to the editor.
- Stop the server when done.

- [ ] **Step 3: Report**

Summarize: cursor fixed globally, posts table delete gone, the three drawers share
the Delete/Cancel/Save controls. Fix and re-verify anything off before declaring done.

---

## Self-review notes

- **Spec coverage:** §1 cursor → Task 4; §2 remove posts delete → Task 3; §3 shared
  components → Task 1 (define) + Task 2 (adopt in reading/gallery/editor); §4 testing
  → Task 1 component tests, Task 2 LiveView suites, Task 5 precommit + browser.
- **Name/type consistency:** `delete_button/1` (`event`/`id`/`confirm`/`label`) and
  `drawer_footer/1` (`cancel_path`/`deletable?`/`delete_event`/`delete_id`/
  `delete_confirm`/`save_label`) are defined in Task 1 and called with exactly those
  attrs in Task 2. The "Delete" label is consistent across editor/reading/gallery and
  matches the relabeled test selector.
- **No placeholders:** every step has concrete code/commands; the one judgment call
  (`Components.x` vs bare `<.x>`) is resolved by "match the existing call style in
  each file," which the files already establish (`<Components.drawer>`).
- **Out of scope:** post-editor restructuring; per-photo gallery delete; public site.
