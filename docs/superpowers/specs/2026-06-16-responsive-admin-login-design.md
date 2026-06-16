# Responsive Admin & Login — Design Spec

**Date:** 2026-06-16
**Status:** Approved (pending written review)
**Branch context:** `phoenix-migration`

## Overview

Make the admin pages usable on small screens. Today the admin shell
(`NewtonWeb.Admin.Layouts.admin/1`) is a fixed 224px (`w-56`) always-visible
`<aside>` beside a `px-10` content area — on a phone the sidebar eats the width
and content is crushed. This change turns the sidebar into an **off-canvas drawer
with a hamburger top bar below the `md` breakpoint**, while leaving the desktop
layout (≥768px) exactly as it is. The login page is already responsive (centered
`max-w-sm` card, `px-4` gutters) and needs only a verification pass.

## Decisions (locked during brainstorming)

- **Mobile nav pattern:** off-canvas drawer + hamburger (not a top-nav rebuild or
  a bottom tab bar).
- **Breakpoint:** `md` (768px). `md` and up = current layout untouched; below
  `md` = drawer.
- **Drawer toggle:** a small **client-side JS hook**, not LiveView/server state,
  so it works across every admin LiveView with no per-view changes.
- **Login:** already responsive; verify + minor spacing tweaks only, no redesign.

## Section 1 — Admin shell (the core change)

File: `lib/newton_web/components/admin/layouts.ex` (the `admin/1` component), plus
a colocated JS hook.

### Layout structure

The outer `<div class="flex min-h-screen">` stays. Changes:

- **`<aside>` becomes drawer-on-mobile, static-on-desktop.** Add an `id` (e.g.
  `admin-sidebar`) and responsive classes so that below `md` it is
  `fixed inset-y-0 left-0 z-40 w-56 -translate-x-full transition-transform`
  (off-screen), and at `md:` it is `md:static md:translate-x-0` (the current
  always-visible rail). An open state is represented by a class/attribute the
  hook toggles (e.g. `data-open` → `translate-x-0`).
- **Backdrop.** A sibling `<div id="admin-sidebar-backdrop">` shown only when the
  drawer is open and only below `md` (`md:hidden`), dimming the content; clicking
  it closes the drawer.
- **Mobile top bar.** A new header visible only below `md` (`md:hidden`),
  containing: a hamburger button (`id="admin-nav-toggle"`), the "newton" brand,
  and the existing theme toggle (so theme can be flipped without opening the
  drawer). The desktop layout shows **no** top bar.
- **Content padding fluid.** `<main>` padding becomes `px-4 md:px-10` (keep
  `py-8`; account for the mobile top bar height so content isn't hidden under it).

### Drawer behavior (the JS hook)

A colocated hook (e.g. `.AdminNav`, attached to the shell) owns open/close as
**client-side state only** — no LiveView round-trip, so the shared layout needs
no assigns and no admin LiveView changes:

- Hamburger click → open (set `data-open` on the sidebar + show backdrop).
- Backdrop click, **Escape**, and **navigation** (a nav-link click / LiveView
  page-loading) → close.
- Close on navigation matters because the layout shell persists across live
  navigations, so without it the drawer would stay open after tapping a section.

This mirrors the existing slide-over drawers (publish/gallery), which already use
`phx-mounted`/`phx-remove` transitions, Escape, and click-away — consistent feel.

## Section 2 — Content & list responsive tweaks

- **Posts list rows** (`PostLive.Index`): the fixed `w-28` published-date column
  hides on the narrowest screens (`hidden sm:block` or similar) so title + status
  badge + delete don't collide; the row stays fully tappable (the stretched-link
  pattern is unchanged).
- **Slide-over drawers** (publish, gallery settings, photo): cap width to the
  viewport — `w-full max-w-sm` — so they don't overflow a phone. (Check
  `Components.drawer/1` and the gallery `settings_drawer`.)
- **Editor header** (the `← Posts` / save-state / status badge / Settings / Save
  row): allow it to wrap gracefully on narrow screens (`flex-wrap` + spacing) so
  buttons don't overflow.
- **Reading / Photos lists:** quick pass to confirm rows/grids reflow (the photo
  grid is already responsive `grid` columns; confirm gutters/padding at mobile).

## Section 3 — Login

`lib/newton_web/live/user_live/login.ex` is already `flex min-h-screen
items-center justify-center px-4` with a `w-full max-w-sm` card — responsive by
construction. Scope here is **verification at ~390px** plus minor spacing tweaks
if anything looks cramped. No structural change expected.

## Error handling / edge cases

- **Drawer open across a resize to desktop:** at `md:` the sidebar is forced
  visible (`md:static md:translate-x-0`) and the backdrop is `md:hidden`, so a
  left-open mobile drawer simply becomes the normal rail — no stuck overlay.
- **JS disabled:** the hook is progressive enhancement; without it the sidebar is
  still in the DOM. Acceptable (admin requires a modern browser; the public site
  is unaffected). Not a target scenario.
- **No new server state**, so no new failure modes in the LiveViews.

## Testing approach

Layout work — verification is primarily visual, plus a few structural assertions.

- **Playwright pass at three widths** (~390px mobile, ~768px tablet, desktop),
  logged in:
  - Mobile: top bar + hamburger visible; sidebar hidden initially; hamburger
    opens the drawer; backdrop/Esc/nav-link each close it; no horizontal overflow
    on dashboard, posts list, editor, a gallery, and login.
  - Tablet/desktop: static sidebar, no top bar, layout unchanged from today.
- **LiveView/structural tests** for the stable bits: the admin shell renders the
  hamburger toggle (`#admin-nav-toggle`) and the sidebar carries the nav hook;
  the sidebar still contains the nav links and the Log out / View site actions.
  Keep these behavior-focused (element presence/wiring), not CSS-class snapshots.

## Unit breakdown

- `lib/newton_web/components/admin/layouts.ex` — drawer-able `<aside>`, backdrop,
  mobile top bar, fluid content padding; colocated `.AdminNav` hook.
- `lib/newton_web/live/admin/post_live/index.ex` — responsive row columns.
- `lib/newton_web/components/admin/components.ex` (+ gallery `settings_drawer`) —
  cap slide-over width to viewport.
- `lib/newton_web/live/admin/post_live/editor.ex` — header row wraps on mobile.
- `lib/newton_web/live/user_live/login.ex` — verify; minor tweaks only.

## Out of scope

- Public site responsiveness (this is admin + login only).
- A bottom tab bar or top-nav rebuild (drawer pattern chosen).
- Reworking the desktop layout (≥`md` is unchanged).
- Per-LiveView nav state / server-driven drawer (client-side hook by decision).
