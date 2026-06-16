# Published Post Unsaved-Changes Guard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** For published posts (which don't autosave), show an "Unsaved changes…" indicator when the form differs from the saved post, and confirm before leaving (in-app nav + tab close) while dirty.

**Architecture:** The editor `validate` handler computes a dirty flag for published posts (field comparison vs the saved post) and drives `save_state`; the header indicator is broadened to show it; a hidden `#unsaved-guard` element exposes `data-unsaved` (true only when published + dirty), and a JS hook reads it to drive `beforeunload` and a capture-phase nav-link click intercept.

**Tech Stack:** Phoenix 1.8 LiveView, Tailwind, esbuild, vitest, pnpm.

---

## Context for the implementer

Read the spec first: `docs/superpowers/specs/2026-06-16-published-unsaved-guard-design.md`.

**Current code (`lib/newton_web/live/admin/post_live/editor.ex`):**
- `handle_event("validate", %{"post" => params}, socket)` computes slug/excerpt
  autofill, builds `form`, and ends with
  `|> maybe_schedule_autosave(params, not published?)`. For a published post
  `not published?` is `false`, so `maybe_schedule_autosave/3` is a no-op and
  `save_state` never changes.
- The header indicator (around line 278) is gated to drafts:
  ```heex
  <span :if={Blog.publish_status(@published_at) == :draft} class="text-[0.78rem] text-(--admin-text-subtle)">
    {save_state_label(@save_state)}
  </span>
  ```
- `save_state_label/1`: `:unsaved → "Unsaved changes…"`, `:error → "Couldn't save"`, `_ → "Saved"`.
- The form opens with `<.form for={@form} id="post-form" phx-submit="save" phx-change="validate">` (line ~269), and the header `<div class="mb-4 flex flex-wrap items-center gap-3">` is its first child.
- A successful manual `save/2` already sets `save_state: :saved`; `apply_action(:edit)` loads with `save_state: :saved`.

**Hook pattern:** external files in `assets/js/hooks/*.js` (e.g. `admin_nav.js`) with a vitest `*.test.js` sibling, registered in `assets/js/admin.js`'s `new LiveSocket(..., {hooks: {...colocatedHooks, AdminTheme, AdminNav, MarkdownEditor, ImageDimensions, SortableGrid}})`. Run JS tests with `pnpm -C assets exec vitest run <file>`.

**Rules:** TDD (failing test first). Test behaviors, not CSS. pnpm not npm. `mix precommit` at the end. Verify each `mix test` / `vitest` before committing. Commit messages end with the `Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>` trailer; commits sign via a 1Password SSH agent that intermittently fails with `1Password: failed to fill whole buffer` — retry the same command up to ~4 times if so.

## File structure

| File | Responsibility | Action |
| --- | --- | --- |
| `lib/newton_web/live/admin/post_live/editor.ex` | dirty tracking, indicator, guard element | Modify |
| `test/newton_web/live/admin/post_editor_live_test.exs` | dirty/indicator/guard-attr tests | Modify |
| `assets/js/hooks/unsaved_guard.js` | beforeunload + nav-intercept hook | Create |
| `assets/js/hooks/unsaved_guard.test.js` | vitest for the hook | Create |
| `assets/js/admin.js` | register `UnsavedGuard` | Modify |

---

## Task 1: Server dirty tracking, indicator, and guard element

**Files:**
- Modify: `lib/newton_web/live/admin/post_live/editor.ex`
- Test: `test/newton_web/live/admin/post_editor_live_test.exs`

- [ ] **Step 1: Write the failing tests**

Add to `test/newton_web/live/admin/post_editor_live_test.exs`:

```elixir
  test "editing a published post flags unsaved changes and the leave guard", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{
        title: "Live",
        slug: "guard-live",
        body_markdown: "body",
        published_at: ~U[2026-01-01 12:00:00Z]
      })

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")
    assert has_element?(view, "#unsaved-guard[data-unsaved='false']")

    view
    |> form("#post-form", post: %{title: "Live Edited", slug: "guard-live", body_markdown: "body"})
    |> render_change()

    assert render(view) =~ "Unsaved changes"
    assert has_element?(view, "#unsaved-guard[data-unsaved='true']")
  end

  test "saving a published post clears the unsaved flag", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{
        title: "Live",
        slug: "guard-save",
        body_markdown: "body",
        published_at: ~U[2026-01-01 12:00:00Z]
      })

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")

    view
    |> form("#post-form", post: %{title: "Live Edited", slug: "guard-save", body_markdown: "body"})
    |> render_change()

    view
    |> form("#post-form", post: %{title: "Live Edited", slug: "guard-save", body_markdown: "body"})
    |> render_submit()

    assert has_element?(view, "#unsaved-guard[data-unsaved='false']")
    refute render(view) =~ "Unsaved changes"
  end

  test "re-typing the saved values leaves a published post not dirty", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{
        title: "Live",
        slug: "guard-same",
        body_markdown: "body",
        published_at: ~U[2026-01-01 12:00:00Z]
      })

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")

    view
    |> form("#post-form", post: %{title: "Live", slug: "guard-same", body_markdown: "body"})
    |> render_change()

    assert has_element?(view, "#unsaved-guard[data-unsaved='false']")
  end

  test "a draft never sets the unsaved leave guard", %{conn: conn} do
    {view, _post} = open_draft(conn)

    view
    |> form("#post-form", post: %{title: "Typing a draft", slug: "typing-a-draft"})
    |> render_change()

    assert has_element?(view, "#unsaved-guard[data-unsaved='false']")
  end
```

(`open_draft/2` is the existing helper at the top of this test file.)

- [ ] **Step 2: Run them to verify they fail**

Run: `mix test test/newton_web/live/admin/post_editor_live_test.exs`
Expected: FAIL — no `#unsaved-guard` element; the indicator is draft-only.

- [ ] **Step 3: Add the dirty check to `validate`**

In `lib/newton_web/live/admin/post_live/editor.ex`, change the end of
`handle_event("validate", ...)` from:

```elixir
     |> assign(:excerpt_auto, excerpt_auto)
     |> maybe_schedule_autosave(params, not published?)}
  end
```

to:

```elixir
     |> assign(:excerpt_auto, excerpt_auto)
     |> track_save_state(params, published?)}
  end
```

Add these private helpers (place them just above `maybe_schedule_autosave/3`):

```elixir
  defp track_save_state(socket, params, false), do: maybe_schedule_autosave(socket, params, true)

  defp track_save_state(socket, params, true) do
    state = if dirty?(socket.assigns.post, params), do: :unsaved, else: :saved
    assign(socket, :save_state, state)
  end

  defp dirty?(post, params) do
    params["title"] != post.title or
      params["slug"] != post.slug or
      (params["body_markdown"] || "") != (post.body_markdown || "") or
      (params["excerpt"] || "") != (post.excerpt || "")
  end
```

- [ ] **Step 4: Broaden the indicator + add the guard element**

In `render/1`, change the indicator's `:if` so it also shows for a dirty
published post. Replace:

```heex
          <span
            :if={Blog.publish_status(@published_at) == :draft}
            class="text-[0.78rem] text-(--admin-text-subtle)"
          >
            {save_state_label(@save_state)}
          </span>
```

with:

```heex
          <span
            :if={Blog.publish_status(@published_at) == :draft or @save_state != :saved}
            class="text-[0.78rem] text-(--admin-text-subtle)"
          >
            {save_state_label(@save_state)}
          </span>
```

Add the guard element as the first child of the form, immediately after the
`<.form ...>` opening tag and before the `<div class="mb-4 flex flex-wrap ...">`:

```heex
      <.form for={@form} id="post-form" phx-submit="save" phx-change="validate">
        <div
          id="unsaved-guard"
          phx-hook="UnsavedGuard"
          data-unsaved={to_string(@save_state == :unsaved and not is_nil(@published_at))}
        >
        </div>
        <div class="mb-4 flex flex-wrap items-center gap-3">
```

- [ ] **Step 5: Run the tests to verify they pass**

Run: `mix test test/newton_web/live/admin/post_editor_live_test.exs`
Expected: PASS — all editor tests green (new ones plus the existing suite; the
draft autosave path is unchanged since `track_save_state(_, _, false)` delegates
to `maybe_schedule_autosave(socket, params, true)`).

- [ ] **Step 6: Compile clean**

Run: `mix compile --warnings-as-errors 2>&1 | tail -3`
Expected: clean (the `phx-hook="UnsavedGuard"` references a hook added in Task 2;
that's fine — HEEx doesn't validate hook names, and LiveView tests don't run JS).

- [ ] **Step 7: Commit**

```bash
git add lib/newton_web/live/admin/post_live/editor.ex test/newton_web/live/admin/post_editor_live_test.exs
git commit -m "Track unsaved changes on published posts in the editor

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 2: UnsavedGuard JS hook

**Files:**
- Create: `assets/js/hooks/unsaved_guard.js`, `assets/js/hooks/unsaved_guard.test.js`
- Modify: `assets/js/admin.js`

- [ ] **Step 1: Write the failing test**

Create `assets/js/hooks/unsaved_guard.test.js`:

```js
import {describe, it, expect, beforeEach, vi, afterEach} from "vitest"
import {UnsavedGuard} from "./unsaved_guard"

function mount(unsaved) {
  document.body.innerHTML = `
    <div id="unsaved-guard" data-unsaved="${unsaved}"></div>
    <a id="nav" href="/admin/posts" data-phx-link="redirect">Posts</a>
  `
  const el = document.getElementById("unsaved-guard")
  const hook = Object.create(UnsavedGuard)
  hook.el = el
  hook.mounted()
  return {hook, el, link: document.getElementById("nav")}
}

const fireBeforeUnload = () => {
  const e = new Event("beforeunload", {cancelable: true})
  window.dispatchEvent(e)
  return e
}
const clickLink = (link) => {
  const e = new MouseEvent("click", {bubbles: true, cancelable: true})
  link.dispatchEvent(e)
  return e
}

describe("UnsavedGuard hook", () => {
  beforeEach(() => (document.body.innerHTML = ""))
  afterEach(() => vi.restoreAllMocks())

  it("prevents unload when dirty", () => {
    mount("true")
    expect(fireBeforeUnload().defaultPrevented).toBe(true)
  })

  it("allows unload when not dirty", () => {
    mount("false")
    expect(fireBeforeUnload().defaultPrevented).toBe(false)
  })

  it("blocks a nav-link click when dirty and the user cancels confirm", () => {
    const {link} = mount("true")
    vi.spyOn(window, "confirm").mockReturnValue(false)
    expect(clickLink(link).defaultPrevented).toBe(true)
  })

  it("allows a nav-link click when dirty and the user accepts confirm", () => {
    const {link} = mount("true")
    vi.spyOn(window, "confirm").mockReturnValue(true)
    expect(clickLink(link).defaultPrevented).toBe(false)
  })

  it("allows a nav-link click when not dirty without confirming", () => {
    const {link} = mount("false")
    const confirm = vi.spyOn(window, "confirm")
    expect(clickLink(link).defaultPrevented).toBe(false)
    expect(confirm).not.toHaveBeenCalled()
  })

  it("stops guarding after destroyed()", () => {
    const {hook} = mount("true")
    hook.destroyed()
    expect(fireBeforeUnload().defaultPrevented).toBe(false)
  })
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `pnpm -C assets exec vitest run hooks/unsaved_guard.test.js`
Expected: FAIL — `./unsaved_guard` does not exist.

- [ ] **Step 3: Implement the hook**

Create `assets/js/hooks/unsaved_guard.js`:

```js
// Warns before leaving the post editor with unsaved changes on a published post.
// Driven by data-unsaved on this.el (the server sets it true only when published
// AND dirty). Guards browser tab close/refresh via the native beforeunload prompt
// and in-app LiveView navigation via a capture-phase click intercept on nav links.

export const UnsavedGuard = {
  mounted() {
    this.dirty = () => this.el.dataset.unsaved === "true"

    this.onBeforeUnload = (e) => {
      if (this.dirty()) {
        e.preventDefault()
        e.returnValue = ""
      }
    }
    window.addEventListener("beforeunload", this.onBeforeUnload)

    this.onClick = (e) => {
      if (!this.dirty()) return
      if (!e.target.closest("a[data-phx-link]")) return
      if (!window.confirm("You have unsaved changes. Leave without saving?")) {
        e.preventDefault()
        e.stopPropagation()
      }
    }
    // Capture phase so we can block LiveView's own click handler.
    document.addEventListener("click", this.onClick, true)
  },

  destroyed() {
    window.removeEventListener("beforeunload", this.onBeforeUnload)
    document.removeEventListener("click", this.onClick, true)
  }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `pnpm -C assets exec vitest run hooks/unsaved_guard.test.js`
Expected: PASS — all 6 tests green.

- [ ] **Step 5: Register the hook**

In `assets/js/admin.js`, add `import {UnsavedGuard} from "./hooks/unsaved_guard"`
with the other hook imports, and add `UnsavedGuard` to the hooks object:

```js
  hooks: {...colocatedHooks, AdminTheme, AdminNav, UnsavedGuard, MarkdownEditor, ImageDimensions, SortableGrid},
```

- [ ] **Step 6: Commit**

```bash
git add assets/js/hooks/unsaved_guard.js assets/js/hooks/unsaved_guard.test.js assets/js/admin.js
git commit -m "Add UnsavedGuard hook to confirm leaving with unsaved edits

Co-Authored-By: Claude Opus 4.8 <noreply@anthropic.com>"
```

---

## Task 3: Verification

**Files:** none (verification only)

- [ ] **Step 1: Full suites**

Run: `pnpm -C assets exec vitest run` then `mix precommit`
Expected: vitest green (incl. `unsaved_guard.test.js`); precommit green (compile
`--warnings-as-errors`, format, Credo, tests, Dialyzer 0).

- [ ] **Step 2: Build assets**

Run: `mix assets.build`
Expected: succeeds (esbuild bundles `admin.js` with `UnsavedGuard`).

- [ ] **Step 3: Playwright confirm-dialog check (start one dev server; stop it after)**

Start `mix phx.server`, log in (`hello@jamesnewton.com` / `password1234`). Create or
open a **published** post's editor. Using Playwright:
- Register a dialog handler that records and dismisses dialogs
  (`page.on("dialog", d => { saw = true; d.dismiss() })`).
- Edit the title (`fill #post_title`), then click the "← Posts" link.
- Assert a confirm dialog fired (`saw === true`) and the URL is still the editor
  (dismiss kept you there).
- Then accept on a second attempt (`d.accept()`) and assert navigation to
  `/admin/posts`.
- Also confirm an **unedited** published post lets you click "← Posts" with no
  dialog.
- Clean up any post created for the check; stop the server when done.

- [ ] **Step 4: Report results**

Summarize: indicator behavior, guard on nav + tab close, draft unaffected. Fix and
re-verify anything that misbehaves before declaring done.

---

## Self-review notes

- **Spec coverage:** Section 1 dirty tracking → Task 1 (Step 3 `dirty?`/`track_save_state`). Section 2 indicator → Task 1 (Step 4). Section 3 leave guard → Task 1 guard element (Step 4) + Task 2 hook. Section 4 testing → Task 1 LiveView tests, Task 2 vitest, Task 3 Playwright.
- **Name/type consistency:** `#unsaved-guard` id, `data-unsaved` attribute, `UnsavedGuard` hook name, and the `data-unsaved === "true"` string check are identical across the editor markup (Task 1), the hook + its test (Task 2), and the LiveView tests. `track_save_state/3` and `dirty?/2` are defined once and used in `validate`.
- **Published-only correctness:** `data-unsaved` is gated by `not is_nil(@published_at)`, and `save_state == :unsaved` for published is only ever set by `track_save_state(_, _, true)`; drafts go through `maybe_schedule_autosave` unchanged, so their guard attr stays `false` (verified by the draft test).
- **No placeholders:** all code/commands are concrete; the Playwright step lists exact assertions.
- **Out of scope:** autosaving published posts; guarding drafts; a custom modal.
