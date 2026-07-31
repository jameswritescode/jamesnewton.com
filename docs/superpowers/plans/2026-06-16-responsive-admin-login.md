# Responsive Admin & Login Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make the admin usable on phones by turning the fixed sidebar into an off-canvas drawer (hamburger top bar) below `md`, leaving desktop unchanged; verify login on mobile.

**Architecture:** A client-side JS hook (`AdminNav`, external file like the other admin hooks) toggles the sidebar drawer + backdrop; the `admin/1` layout component adds drawer/rail responsive classes, a backdrop, and a `md:hidden` mobile top bar. No LiveView/server state, so every admin LiveView gets it for free. Lists/drawers/editor header get small responsive tweaks.

**Tech Stack:** Phoenix 1.8 LiveView, Tailwind v4, esbuild, vitest (JS hook tests), pnpm.

---

## Context for the implementer

Read the spec first: `docs/superpowers/specs/2026-06-16-responsive-admin-login-design.md`.

**Current code:**
- `lib/newton_web/components/admin/layouts.ex` — `admin/1` renders
  `<div class="flex min-h-screen">` → a `<aside class="sticky top-0 flex h-screen w-56 shrink-0 …">` (nav + footer: View site / Log out / `#admin-theme-toggle` with `phx-hook="AdminTheme"`) → `<main id="admin-main" class="max-w-6xl flex-1 px-10 py-8">`.
- **Hook pattern:** external files in `assets/js/hooks/*.js`, each with a vitest `*.test.js`, registered in `assets/js/admin.js` (`hooks: {...colocatedHooks, AdminTheme, MarkdownEditor, ImageDimensions, SortableGrid}`). The hook object exposes `mounted()`/`destroyed()` and uses `this.el`.
- `assets/package.json` → `"test": "vitest run"`. Run JS tests with `pnpm -C assets exec vitest run <file>`.
- LiveView page navigations dispatch the `phx:page-loading-start` window event — use it to close the drawer on navigation.

**Rules:** TDD for the hook (vitest, failing test first). pnpm, never npm. Test behaviors not CSS classes for LiveView tests. The layout/CSS itself is verified **visually via Playwright** (Task 5), not unit tests — that's expected for pure-styling changes. `mix precommit` at the end. Verify each `mix test`/`vitest` before committing.

## File structure

| File | Responsibility | Action |
| --- | --- | --- |
| `assets/js/hooks/admin_nav.js` | Drawer open/close/backdrop/Esc/close-on-nav | Create |
| `assets/js/hooks/admin_nav.test.js` | vitest for the hook | Create |
| `assets/js/admin.js` | register `AdminNav` | Modify |
| `lib/newton_web/components/admin/layouts.ex` | drawer aside, backdrop, mobile top bar, fluid padding | Modify |
| `test/newton_web/live/admin/admin_shell_test.exs` | structural shell assertions | Create |
| `lib/newton_web/live/admin/post_live/index.ex` | responsive row date column | Modify |
| `lib/newton_web/components/admin/components.ex` | cap drawer width to viewport | Modify |
| `lib/newton_web/live/admin/post_live/editor.ex` | header row wraps on mobile | Modify |

---

## Task 1: AdminNav hook (TDD with vitest)

**Files:**
- Create: `assets/js/hooks/admin_nav.js`, `assets/js/hooks/admin_nav.test.js`
- Modify: `assets/js/admin.js`

- [ ] **Step 1: Write the failing test**

Create `assets/js/hooks/admin_nav.test.js`:

```js
import {describe, it, expect, beforeEach} from "vitest"
import {AdminNav} from "./admin_nav"

function setup() {
  document.body.innerHTML = `
    <button id="admin-nav-toggle">menu</button>
    <aside id="admin-sidebar" class="-translate-x-full"></aside>
    <div id="admin-sidebar-backdrop" class="hidden"></div>
  `
  const toggle = document.getElementById("admin-nav-toggle")
  const hook = Object.create(AdminNav)
  hook.el = toggle
  hook.mounted()
  return {
    toggle,
    sidebar: document.getElementById("admin-sidebar"),
    backdrop: document.getElementById("admin-sidebar-backdrop")
  }
}

const isOpen = (sidebar, backdrop) =>
  sidebar.classList.contains("translate-x-0") &&
  !sidebar.classList.contains("-translate-x-full") &&
  !backdrop.classList.contains("hidden")

describe("AdminNav hook", () => {
  beforeEach(() => (document.body.innerHTML = ""))

  it("opens the drawer when the toggle is clicked", () => {
    const {toggle, sidebar, backdrop} = setup()
    toggle.dispatchEvent(new MouseEvent("click", {bubbles: true}))
    expect(isOpen(sidebar, backdrop)).toBe(true)
  })

  it("closes on backdrop click", () => {
    const {toggle, sidebar, backdrop} = setup()
    toggle.dispatchEvent(new MouseEvent("click", {bubbles: true}))
    backdrop.dispatchEvent(new MouseEvent("click", {bubbles: true}))
    expect(isOpen(sidebar, backdrop)).toBe(false)
  })

  it("closes on Escape", () => {
    const {toggle, sidebar, backdrop} = setup()
    toggle.dispatchEvent(new MouseEvent("click", {bubbles: true}))
    document.dispatchEvent(new KeyboardEvent("keydown", {key: "Escape"}))
    expect(isOpen(sidebar, backdrop)).toBe(false)
  })

  it("closes on navigation (phx:page-loading-start)", () => {
    const {toggle, sidebar, backdrop} = setup()
    toggle.dispatchEvent(new MouseEvent("click", {bubbles: true}))
    window.dispatchEvent(new Event("phx:page-loading-start"))
    expect(isOpen(sidebar, backdrop)).toBe(false)
  })
})
```

- [ ] **Step 2: Run it to verify it fails**

Run: `pnpm -C assets exec vitest run hooks/admin_nav.test.js`
Expected: FAIL — `./admin_nav` does not exist.

- [ ] **Step 3: Implement the hook**

Create `assets/js/hooks/admin_nav.js`:

```js
// Mobile admin navigation drawer. Below the `md` breakpoint the sidebar is an
// off-canvas drawer; this hook (attached to the hamburger button) toggles it,
// with a backdrop, Escape, and auto-close on LiveView navigation. Desktop is
// unaffected — md: classes keep the sidebar visible regardless of these toggles.

function setOpen(open) {
  const sidebar = document.getElementById("admin-sidebar")
  const backdrop = document.getElementById("admin-sidebar-backdrop")
  if (!sidebar || !backdrop) return
  sidebar.classList.toggle("translate-x-0", open)
  sidebar.classList.toggle("-translate-x-full", !open)
  backdrop.classList.toggle("hidden", !open)
}

export const AdminNav = {
  mounted() {
    this.open = () => setOpen(true)
    this.close = () => setOpen(false)

    this.el.addEventListener("click", this.open)

    this.backdrop = document.getElementById("admin-sidebar-backdrop")
    if (this.backdrop) this.backdrop.addEventListener("click", this.close)

    this.onKeydown = (e) => {
      if (e.key === "Escape") this.close()
    }
    document.addEventListener("keydown", this.onKeydown)

    window.addEventListener("phx:page-loading-start", this.close)
  },

  destroyed() {
    this.el.removeEventListener("click", this.open)
    if (this.backdrop) this.backdrop.removeEventListener("click", this.close)
    document.removeEventListener("keydown", this.onKeydown)
    window.removeEventListener("phx:page-loading-start", this.close)
  }
}
```

- [ ] **Step 4: Run it to verify it passes**

Run: `pnpm -C assets exec vitest run hooks/admin_nav.test.js`
Expected: PASS — all 4 tests green.

- [ ] **Step 5: Register the hook in admin.js**

In `assets/js/admin.js`, add the import next to the others:

```js
import {AdminNav} from "./hooks/admin_nav"
```

and add `AdminNav` to the hooks object:

```js
  hooks: {...colocatedHooks, AdminTheme, AdminNav, MarkdownEditor, ImageDimensions, SortableGrid},
```

- [ ] **Step 6: Commit**

```bash
git add assets/js/hooks/admin_nav.js assets/js/hooks/admin_nav.test.js assets/js/admin.js
git commit -m "Add AdminNav hook for the mobile admin drawer"
```

---

## Task 2: Admin shell — drawer, backdrop, mobile top bar

**Files:**
- Modify: `lib/newton_web/components/admin/layouts.ex`
- Test: `test/newton_web/live/admin/admin_shell_test.exs`

- [ ] **Step 1: Write the structural test**

Create `test/newton_web/live/admin/admin_shell_test.exs`:

```elixir
defmodule NewtonWeb.Admin.AdminShellTest do
  use NewtonWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Newton.AccountsFixtures

  setup %{conn: conn} do
    %{conn: log_in_user(conn, user_fixture())}
  end

  test "the admin shell renders the mobile nav toggle wired to the drawer", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin")

    assert has_element?(view, "#admin-nav-toggle[phx-hook='AdminNav']")
    assert has_element?(view, "#admin-sidebar")
    assert has_element?(view, "#admin-sidebar-backdrop")
  end

  test "the sidebar still holds the nav and account actions", %{conn: conn} do
    {:ok, view, _html} = live(conn, ~p"/admin")

    assert has_element?(view, "#admin-sidebar a", "Posts")
    assert has_element?(view, "#admin-sidebar a", "Log out")
  end
end
```

- [ ] **Step 2: Run it to verify it fails**

Run: `mix test test/newton_web/live/admin/admin_shell_test.exs`
Expected: FAIL — no `#admin-nav-toggle` / `#admin-sidebar` ids yet.

- [ ] **Step 3: Rewrite the `admin/1` markup**

In `lib/newton_web/components/admin/layouts.ex`, replace the `~H"""..."""` body of `admin/1` (the `<div class="flex min-h-screen">…</div>`) with:

```heex
    <div class="flex min-h-screen">
      <aside
        id="admin-sidebar"
        class="fixed inset-y-0 left-0 z-40 flex h-screen w-56 -translate-x-full flex-col border-r border-(--admin-border) bg-(--admin-sidebar) px-3 py-[1.1rem] transition-transform duration-200 md:sticky md:top-0 md:translate-x-0 md:shrink-0 md:transition-none"
      >
        <div class="flex items-center gap-2 px-[0.6rem] pb-[1.1rem] text-[0.95rem] font-semibold tracking-tight">
          <span class="size-2 rounded-full bg-(--admin-accent)"></span> newton
        </div>

        <nav class="flex flex-1 flex-col gap-0.5">
          <.nav_item
            :for={section <- @sections}
            section={section}
            current={@current}
            built={section.key in @built}
          />
        </nav>

        <div class="mt-[0.6rem] flex flex-col gap-0.5 border-t border-(--admin-border) pt-[0.6rem]">
          <.link
            href={~p"/"}
            class="flex items-center gap-2 rounded-md px-[0.6rem] py-[0.4rem] text-[0.8rem] text-(--admin-text-muted) no-underline transition-colors hover:bg-(--admin-accent-soft) hover:text-(--admin-text)"
          >
            <.icon name="hero-arrow-top-right-on-square-mini" class="size-4" /> View site
          </.link>
          <.link
            href={~p"/logout"}
            method="delete"
            class="flex items-center gap-2 rounded-md px-[0.6rem] py-[0.4rem] text-[0.8rem] text-(--admin-text-muted) no-underline transition-colors hover:bg-(--admin-accent-soft) hover:text-(--admin-text)"
          >
            <.icon name="hero-arrow-right-start-on-rectangle-mini" class="size-4" /> Log out
          </.link>
          <button
            id="admin-theme-toggle"
            type="button"
            class="flex w-full items-center gap-2 rounded-md px-[0.6rem] py-[0.4rem] text-[0.8rem] text-(--admin-text-muted) transition-colors hover:bg-(--admin-accent-soft) hover:text-(--admin-text)"
            phx-hook="AdminTheme"
            aria-label="Toggle light or dark theme"
          >
            <.icon name="hero-sun-mini" class="size-4 admin-dark:hidden" />
            <.icon name="hero-moon-mini" class="hidden size-4 admin-dark:inline-flex" />
            <span class="admin-dark:hidden">Light</span>
            <span class="hidden admin-dark:inline">Dark</span>
          </button>
        </div>
      </aside>

      <div id="admin-sidebar-backdrop" class="fixed inset-0 z-30 hidden bg-black/40 md:hidden"></div>

      <div class="flex min-w-0 flex-1 flex-col">
        <header class="flex items-center gap-3 border-b border-(--admin-border) bg-(--admin-sidebar) px-4 py-3 md:hidden">
          <button
            id="admin-nav-toggle"
            type="button"
            phx-hook="AdminNav"
            aria-label="Open menu"
            class="rounded-md p-1 text-(--admin-text-muted) hover:bg-(--admin-accent-soft) hover:text-(--admin-text)"
          >
            <.icon name="hero-bars-3" class="size-5" />
          </button>
          <span class="flex items-center gap-2 text-[0.95rem] font-semibold tracking-tight">
            <span class="size-2 rounded-full bg-(--admin-accent)"></span> newton
          </span>
          <div class="flex-1"></div>
          <button
            id="admin-theme-toggle-mobile"
            type="button"
            class="rounded-md p-1 text-(--admin-text-muted) hover:bg-(--admin-accent-soft) hover:text-(--admin-text)"
            phx-hook="AdminTheme"
            aria-label="Toggle light or dark theme"
          >
            <.icon name="hero-sun-mini" class="size-5 admin-dark:hidden" />
            <.icon name="hero-moon-mini" class="hidden size-5 admin-dark:inline-flex" />
          </button>
        </header>

        <main id="admin-main" class="max-w-6xl flex-1 px-4 py-8 md:px-10">
          {render_slot(@inner_block)}
        </main>
      </div>
      <.admin_flash_group flash={@flash} />
    </div>
```

Notes: the sidebar is `fixed` + off-canvas on mobile and `md:sticky md:translate-x-0` (the original rail) on desktop; the backdrop and top bar are `md:hidden`; `min-w-0` on the content column prevents overflow; a second AdminTheme button (`#admin-theme-toggle-mobile`) lives in the top bar (two AdminTheme hooks coexist — each just flips the global `data-admin-theme`).

- [ ] **Step 4: Run the structural test**

Run: `mix test test/newton_web/live/admin/admin_shell_test.exs`
Expected: PASS.

- [ ] **Step 5: Confirm no admin LiveView tests broke + clean compile**

Run: `mix compile --warnings-as-errors 2>&1 | tail -3` and `mix test test/newton_web/live/admin/`
Expected: clean compile; all admin LiveView tests pass (the shell markup change shouldn't affect their assertions — they target inner content and ids that are unchanged).

- [ ] **Step 6: Commit**

```bash
git add lib/newton_web/components/admin/layouts.ex test/newton_web/live/admin/admin_shell_test.exs
git commit -m "Make the admin sidebar an off-canvas drawer on mobile"
```

---

## Task 3: Content & list responsive tweaks

**Files:**
- Modify: `lib/newton_web/live/admin/post_live/index.ex`, `lib/newton_web/components/admin/components.ex`, `lib/newton_web/live/admin/post_live/editor.ex`

These are styling-only; verification is the Task 5 Playwright pass. No new tests (behavior unchanged).

- [ ] **Step 1: Posts list — hide the date column on the narrowest screens**

In `lib/newton_web/live/admin/post_live/index.ex`, the post row has a date span:

```heex
          <span class="w-28 text-right text-[0.78rem] text-(--admin-text-subtle)">
            {format_date(post.published_at)}
          </span>
```

Change its class to hide below `sm`:

```heex
          <span class="hidden w-28 text-right text-[0.78rem] text-(--admin-text-subtle) sm:block">
            {format_date(post.published_at)}
          </span>
```

- [ ] **Step 2: Guard the slide-over drawer width on tiny screens**

In `lib/newton_web/components/admin/components.ex`, the `drawer/1` panel element is
(line ~37):

```heex
      class="fixed inset-y-0 right-0 z-20 flex w-80 flex-col gap-4 overflow-y-auto border-l border-(--admin-border) bg-(--admin-sidebar) p-5 shadow-xl"
```

`w-80` (320px) already fits any phone ≥320px, but on narrower screens it would
overflow and leave no backdrop to tap. Add a max-width guard so the panel never
exceeds the viewport minus a gutter — keep `w-80`, add `max-w-[calc(100vw-3rem)]`:

```heex
      class="fixed inset-y-0 right-0 z-20 flex w-80 max-w-[calc(100vw-3rem)] flex-col gap-4 overflow-y-auto border-l border-(--admin-border) bg-(--admin-sidebar) p-5 shadow-xl"
```

(The gallery `settings_drawer` in `lib/newton_web/live/admin/gallery_live/components.ex` reuses this `drawer/1`, so no separate change is needed there. Confirm with `grep -n "w-80" lib/newton_web/live/admin/gallery_live/components.ex` — if it has its own panel width, apply the same guard.)

- [ ] **Step 3: Editor header — wrap on narrow screens**

In `lib/newton_web/live/admin/post_live/editor.ex`, the header row is:

```heex
        <div class="mb-4 flex items-center gap-3">
```

Allow wrapping so the `← Posts` / save-state / badge / Settings / Save controls don't overflow on a phone:

```heex
        <div class="mb-4 flex flex-wrap items-center gap-3">
```

- [ ] **Step 4: Compile + run the affected suites**

Run: `mix compile --warnings-as-errors 2>&1 | tail -3` and `mix test test/newton_web/live/admin/`
Expected: clean compile; all admin LiveView tests pass (these are class-only edits).

- [ ] **Step 5: Commit**

```bash
git add lib/newton_web/live/admin/post_live/index.ex lib/newton_web/components/admin/components.ex lib/newton_web/live/admin/post_live/editor.ex
git commit -m "Reflow admin lists, drawers, and the editor header on small screens"
```

(If `lib/newton_web/live/admin/gallery_live/components.ex` was also edited in Step 2, include it in the `git add`.)

---

## Task 4: Login verification

**Files:** `lib/newton_web/live/user_live/login.ex` (likely no change)

- [ ] **Step 1: Confirm the login layout is already fluid**

Run: `grep -n "min-h-screen\|max-w-sm\|px-4\|w-full" lib/newton_web/live/user_live/login.ex`
Expected: the outer wrapper is `flex min-h-screen items-center justify-center px-4` and the card is `w-full max-w-sm` — already responsive. If both are present, **no change needed** (the Task 5 Playwright pass confirms it visually). Only if something looks cramped at 390px (found in Task 5), nudge spacing (e.g. card `p-6` → `p-5 sm:p-6`) and commit then.

---

## Task 5: Verification (vitest + mix + Playwright at 3 widths)

**Files:** none (verification only)

- [ ] **Step 1: JS + Elixir suites**

Run: `pnpm -C assets exec vitest run` then `mix precommit`
Expected: vitest green (incl. `admin_nav.test.js`); precommit green (compile `--warnings-as-errors`, format, Credo, tests, Dialyzer 0).

- [ ] **Step 2: Build assets so the new hook is in the bundle**

Run: `mix assets.build`
Expected: succeeds (esbuild bundles `admin.js` with `AdminNav`).

- [ ] **Step 3: Playwright pass at three widths (start one dev server; stop it after)**

Start `mix phx.server`. Log in (your local admin credentials). Using Playwright (the `assets/screenshot.mjs` pattern), at viewport widths **390** (mobile), **768** (tablet), and **1280** (desktop), on `/admin`, `/admin/posts`, a post editor, and a gallery:
  - **390:** the mobile top bar + `#admin-nav-toggle` are visible; `#admin-sidebar` is off-canvas initially (its box is left of x=0 / not visible); clicking the hamburger opens it (sidebar visible, `#admin-sidebar-backdrop` shown); clicking the backdrop closes it; pressing Escape closes it; clicking a nav link navigates and the drawer is closed afterward; `document.documentElement.scrollWidth <= window.innerWidth` (no horizontal overflow) on each page; the login page (logged out) shows the centered card with no overflow.
  - **768 and 1280:** the static sidebar is visible, the mobile top bar (`md:hidden`) is hidden, and the layout matches today.
  - Stop the server when done (don't leave it running).

- [ ] **Step 4: Report results**

Summarize the three-width results (pass/fail per check). If anything overflows or the drawer misbehaves, fix and re-verify before declaring done.

---

## Self-review notes

- **Spec coverage:** Section 1 admin shell → Tasks 1–2 (hook + layout: drawer, backdrop, mobile top bar with theme toggle, fluid padding, close-on-nav/Esc/backdrop). Section 2 content/list tweaks → Task 3 (posts date column, drawer width, editor header). Section 3 login → Task 4. Testing approach → Task 5 (vitest + Playwright three widths + structural LiveView test in Task 2).
- **Honest verification:** the hook logic is properly TDD'd (vitest); the layout/CSS is verified visually (Playwright) — appropriate for pure styling. The structural LiveView test asserts wiring (ids/hook/links), not CSS classes.
- **Type/name consistency:** `AdminNav` (hook), ids `admin-nav-toggle` / `admin-sidebar` / `admin-sidebar-backdrop`, and the `translate-x-0` / `-translate-x-full` / `hidden` toggle classes are identical across the hook (Task 1), its test, the layout markup (Task 2), and the Playwright checks (Task 5).
- **No placeholders:** Task 3 Step 2 gives the exact target (`w-80 max-w-[calc(100vw-3rem)]`); Task 4 is a verify-and-no-op-unless-cramped step with the concrete fallback spelled out.
- **Out of scope:** public-site responsiveness, bottom tab bar / top-nav rebuild, desktop redesign.
