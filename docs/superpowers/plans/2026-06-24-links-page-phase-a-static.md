# /links Phase A — Static Accessible Page — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Ship the complete, accessible, static `/links` page — the Gibson menu of outbound links with a live readout panel — as a full-screen takeover, with no cinematic yet.

**Architecture:** A plain Phoenix controller page (no LiveView). Link data is a hardcoded Elixir module. The template renders its own full-screen `<main id="main" class="links">` and deliberately omits `<Layouts.app>` (and thus the site header) for the takeover. Navigation to/from the page bypasses Swup (`data-no-swup`) so the persistent header can't bleed in. A small vanilla JS module wires hover/focus on menu items to the readout panel. The page works with no JS (readout defaults to the first link, server-rendered).

**Tech Stack:** Elixir/Phoenix (controller + HEEx), Tailwind v4 + a scoped `links.css`, vanilla JS (no three.js in this phase), ExUnit, vitest.

**Context for the implementer:**
- This is Phase A of three. Phases B (mosaic page transition) and C (three.js cinematic) are separate plans and are NOT in scope here.
- Public pages are controllers rendered inside `lib/newton_web/components/layouts/root.html.heex`. Normal pages wrap content in `<Layouts.app>` which renders `<.site_header>` *outside* `#main`; this page must NOT do that.
- The site uses **Swup** (`assets/js/app.js`) to swap only `#main` on same-origin link clicks. Because the header lives outside `#main`, a Swup swap into `/links` would leave the previous page's header on screen. We avoid this by marking the inbound and outbound links `data-no-swup` (full-document navigation).
- Page-specific JS follows the `initPhotos()` pattern in `assets/js/app.js`: a module exporting an `init` function, called on first load and on Swup `content:replace`.
- Design spec: `docs/superpowers/specs/2026-06-24-links-page-hackers-design.md`.

**Confirmed link set (real values — use exactly these):**
| name | url | description |
|------|-----|-------------|
| GITHUB | https://github.com/jameswritescode | Code, experiments, and the source of this very site. |
| LINKEDIN | https://www.linkedin.com/in/jameswritescode | The professional paper trail. |
| BLUESKY | https://bsky.app/profile/jamesnewton.com | Short thoughts, mostly about software and craft. |
| MARK OS | https://markos.ai | Where I work. We think about how software gets built. |
| EMAIL | mailto:hello@jamesnewton.com | Say hello. I read everything. |

RSS is intentionally omitted until the feed exists (a commented entry documents this).

---

### Task 1: `Newton.Links` data module

**Files:**
- Create: `lib/newton/links.ex`
- Test: `test/newton/links_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
# test/newton/links_test.exs
defmodule Newton.LinksTest do
  use ExUnit.Case, async: true
  alias Newton.Links

  test "all/0 returns the ordered launch link set" do
    names = Links.all() |> Enum.map(& &1.name)
    assert names == ["GITHUB", "LINKEDIN", "BLUESKY", "MARK OS", "EMAIL"]
  end

  test "each link has a name, url, and description" do
    for link <- Links.all() do
      assert is_binary(link.name) and link.name != ""
      assert is_binary(link.url) and link.url != ""
      assert is_binary(link.description) and link.description != ""
    end
  end

  test "external?/1 is true for http(s) urls and false for mailto and paths" do
    assert Links.external?("https://github.com/jameswritescode")
    assert Links.external?("http://example.com")
    refute Links.external?("mailto:hello@jamesnewton.com")
    refute Links.external?("/")
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/newton/links_test.exs`
Expected: FAIL — `Newton.Links` is undefined.

- [ ] **Step 3: Write minimal implementation**

```elixir
# lib/newton/links.ex
defmodule Newton.Links do
  @moduledoc "The hardcoded set of outbound links shown on the /links page."

  @links [
    %{
      name: "GITHUB",
      url: "https://github.com/jameswritescode",
      description: "Code, experiments, and the source of this very site."
    },
    %{
      name: "LINKEDIN",
      url: "https://www.linkedin.com/in/jameswritescode",
      description: "The professional paper trail."
    },
    %{
      name: "BLUESKY",
      url: "https://bsky.app/profile/jamesnewton.com",
      description: "Short thoughts, mostly about software and craft."
    },
    %{
      name: "MARK OS",
      url: "https://markos.ai",
      description: "Where I work. We think about how software gets built."
    },
    %{
      name: "EMAIL",
      url: "mailto:hello@jamesnewton.com",
      description: "Say hello. I read everything."
    }
    # RSS is deferred until the site has an actual feed. Add once it exists:
    # %{name: "RSS", url: "/feed.xml", description: "Subscribe the old-fashioned way."}
  ]

  @doc "The ordered list of links, each `%{name, url, description}`."
  @spec all() :: [%{name: String.t(), url: String.t(), description: String.t()}]
  def all, do: @links

  @doc "Whether a url points off-site (and should open in a new tab)."
  @spec external?(String.t()) :: boolean()
  def external?(url), do: String.starts_with?(url, "http")
end
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/newton/links_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/newton/links.ex test/newton/links_test.exs
git commit -m "Add Newton.Links hardcoded link data for the /links page"
```

---

### Task 2: Route, controller, and HTML module (page renders)

**Files:**
- Modify: `lib/newton_web/router.ex` (public `:browser` scope, alongside the other `get` routes ~lines 26-33)
- Create: `lib/newton_web/controllers/links_controller.ex`
- Create: `lib/newton_web/controllers/links_html.ex`
- Create: `lib/newton_web/controllers/links_html/index.html.heex`
- Test: `test/newton_web/controllers/links_controller_test.exs`

- [ ] **Step 1: Write the failing test**

```elixir
# test/newton_web/controllers/links_controller_test.exs
defmodule NewtonWeb.LinksControllerTest do
  use NewtonWeb.ConnCase

  test "GET /links renders every link's name and url", %{conn: conn} do
    html = conn |> get(~p"/links") |> html_response(200)

    for link <- Newton.Links.all() do
      assert html =~ link.name
      assert html =~ link.url
    end
  end

  test "GET /links opens external links in a new tab safely", %{conn: conn} do
    html = conn |> get(~p"/links") |> html_response(200)
    assert html =~ ~s(rel="noopener noreferrer")
  end

  test "GET /links offers a way back to the main site", %{conn: conn} do
    html = conn |> get(~p"/links") |> html_response(200)
    assert html =~ "JN.SYS"
  end
end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/newton_web/controllers/links_controller_test.exs`
Expected: FAIL — no route for `/links` (or `NewtonWeb.LinksController` undefined).

- [ ] **Step 3a: Add the route**

In `lib/newton_web/router.ex`, inside the existing public scope (the one with `get "/", PageController, :home`), add:

```elixir
    get "/links", LinksController, :index
```

- [ ] **Step 3b: Add the controller**

```elixir
# lib/newton_web/controllers/links_controller.ex
defmodule NewtonWeb.LinksController do
  use NewtonWeb, :controller

  def index(conn, _params) do
    render(conn, :index, page_title: "Links", links: Newton.Links.all())
  end
end
```

- [ ] **Step 3c: Add the HTML module**

```elixir
# lib/newton_web/controllers/links_html.ex
defmodule NewtonWeb.LinksHTML do
  use NewtonWeb, :html

  embed_templates "links_html/*"

  defdelegate external?(url), to: Newton.Links
end
```

- [ ] **Step 3d: Add a minimal template (full markup comes in Task 3)**

```heex
<%!-- lib/newton_web/controllers/links_html/index.html.heex --%>
<main id="main" class="links" aria-label="Links">
  <ul class="links-menu" role="list">
    <li :for={link <- @links}>
      <a
        class="links-item"
        href={link.url}
        data-name={link.name}
        data-url={link.url}
        data-desc={link.description}
        {if external?(link.url), do: [target: "_blank", rel: "noopener noreferrer"], else: []}
      >
        {link.name}
      </a>
    </li>
    <li>
      <a class="links-item links-item--home" href={~p"/"} data-no-swup>JN.SYS [HOME]</a>
    </li>
  </ul>
</main>
```

- [ ] **Step 4: Run test to verify it passes**

Run: `mix test test/newton_web/controllers/links_controller_test.exs`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/newton_web/router.ex lib/newton_web/controllers/links_controller.ex lib/newton_web/controllers/links_html.ex lib/newton_web/controllers/links_html/index.html.heex test/newton_web/controllers/links_controller_test.exs
git commit -m "Add the /links route, controller, and a minimal takeover page"
```

---

### Task 3: Full takeover template + scoped CSS

**Files:**
- Modify: `lib/newton_web/controllers/links_html/index.html.heex` (replace body of `<main>`)
- Create: `assets/css/links.css`
- Modify: `assets/css/app.css` (add the import next to the `site.css` import)
- Test: `test/newton_web/controllers/links_controller_test.exs` (extend)

- [ ] **Step 1: Extend the test (readout defaults to the first link)**

Add to `test/newton_web/controllers/links_controller_test.exs`:

```elixir
  test "GET /links seeds the readout with the first link (works without JS)", %{conn: conn} do
    html = conn |> get(~p"/links") |> html_response(200)
    first = Newton.Links.all() |> List.first()

    assert html =~ ~s(data-readout="name")
    assert html =~ first.description
  end
```

- [ ] **Step 2: Run test to verify it fails**

Run: `mix test test/newton_web/controllers/links_controller_test.exs`
Expected: FAIL — no `data-readout` markup yet.

- [ ] **Step 3a: Replace the template with the full takeover markup**

```heex
<%!-- lib/newton_web/controllers/links_html/index.html.heex --%>
<main id="main" class="links" aria-label="Links">
  <div class="links-bg" aria-hidden="true"></div>
  <div class="links-scanlines" aria-hidden="true"></div>

  <div class="links-console">
    <ul class="links-menu" role="list">
      <li :for={link <- @links}>
        <a
          class="links-item"
          href={link.url}
          data-name={link.name}
          data-url={link.url}
          data-desc={link.description}
          {if external?(link.url), do: [target: "_blank", rel: "noopener noreferrer"], else: []}
        >
          {link.name}<span class="links-arrow" aria-hidden="true">&#9654;</span>
        </a>
      </li>
      <li>
        <a
          class="links-item links-item--home"
          href={~p"/"}
          data-no-swup
          data-name="JN.SYS"
          data-url="/"
          data-desc="Disconnect. Return to jamesnewton.com."
        >
          <span class="links-arrow" aria-hidden="true">&#9664;</span>JN.SYS [HOME]
        </a>
      </li>
    </ul>

    <aside class="links-readout" aria-hidden="true">
      <div class="links-readout-label">// READOUT</div>
      <div class="links-readout-name" data-readout="name">{List.first(@links).name}</div>
      <div class="links-readout-url" data-readout="url">{List.first(@links).url}</div>
      <div class="links-readout-desc" data-readout="desc">{List.first(@links).description}</div>
      <div class="links-readout-status">&gt; CONNECTION READY</div>
    </aside>
  </div>
</main>
```

- [ ] **Step 3b: Create the scoped stylesheet**

```css
/* assets/css/links.css
   The HACKERS "Gibson" /links page. Everything is scoped under .links so it
   cannot leak into the rest of the site. Single dark scene; its own palette. */
.links {
  --links-cyan: #19c9ff;
  --links-magenta: #ff31d9;
  --links-magenta-soft: #ff5cc8;
  --links-green: #b6ff00;
  --links-bg: #020207;
  --links-mono: "SF Mono", "JetBrains Mono", "Courier New", monospace;
  --links-display: "Arial Narrow", "Roboto Condensed", "Helvetica Neue", system-ui, sans-serif;

  position: relative;
  min-height: 100vh;
  margin: 0;
  overflow: hidden;
  background: var(--links-bg);
  color: var(--links-cyan);
  display: flex;
  align-items: center;
}

/* atmospheric techy background (real scrolling code comes in Phase C) */
.links-bg {
  position: absolute;
  inset: 0;
  background:
    radial-gradient(120% 90% at 50% 18%, #1a0736 0%, var(--links-bg) 60%),
    repeating-linear-gradient(90deg, transparent 0 26px, rgba(58, 160, 184, 0.05) 26px 27px);
  pointer-events: none;
}

.links-scanlines {
  position: absolute;
  inset: 0;
  background: repeating-linear-gradient(0deg, rgba(0, 0, 0, 0.28) 0 1px, transparent 1px 3px);
  pointer-events: none;
}

.links-console {
  position: relative;
  display: flex;
  align-items: center;
  gap: 28px;
  padding: 0 clamp(20px, 6vw, 80px);
}

.links-menu {
  list-style: none;
  margin: 0;
  padding: 0;
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.links-item {
  display: inline-flex;
  align-items: center;
  font-family: var(--links-display);
  font-weight: 700;
  font-size: clamp(28px, 4.5vw, 44px);
  letter-spacing: 0.08em;
  text-transform: uppercase;
  text-decoration: none;
  color: var(--links-cyan);
  text-shadow: 0 0 10px rgba(0, 229, 255, 0.6), 0 0 2px rgba(0, 229, 255, 0.8);
  line-height: 1;
  transition: color 0.1s ease, text-shadow 0.1s ease;
}

.links-arrow {
  margin-left: 0.4em;
  font-size: 0.7em;
  opacity: 0.8;
}

.links-item:hover,
.links-item:focus-visible {
  color: var(--links-magenta-soft);
  text-shadow: 0 0 12px var(--links-magenta), 0 0 3px var(--links-magenta);
  outline: none;
}

.links-item--home {
  color: var(--links-magenta-soft);
  text-shadow: 0 0 10px rgba(255, 49, 217, 0.6);
}

.links-item--home .links-arrow {
  margin-left: 0;
  margin-right: 0.4em;
}

.links-readout {
  width: clamp(240px, 28vw, 320px);
  border: 1.5px solid var(--links-magenta);
  box-shadow: 0 0 16px rgba(255, 49, 217, 0.33), inset 0 0 18px rgba(255, 49, 217, 0.13);
  background: rgba(26, 2, 32, 0.8);
  padding: 18px;
  font-family: var(--links-mono);
}

.links-readout-label {
  color: var(--links-magenta-soft);
  font-size: 13px;
  letter-spacing: 0.2em;
  text-shadow: 0 0 8px var(--links-magenta);
  margin-bottom: 10px;
}

.links-readout-name {
  color: #8ff6ff;
  font-family: var(--links-display);
  font-size: 20px;
  letter-spacing: 0.1em;
  text-shadow: 0 0 8px var(--links-cyan);
  margin-bottom: 8px;
}

.links-readout-url {
  color: var(--links-green);
  font-size: 12px;
  word-break: break-all;
  margin-bottom: 10px;
}

.links-readout-desc {
  color: #bfe9f2;
  font-size: 12px;
  line-height: 1.5;
  opacity: 0.85;
}

.links-readout-status {
  margin-top: 14px;
  color: var(--links-magenta-soft);
  font-size: 11px;
  letter-spacing: 0.15em;
}

@media (max-width: 640px) {
  .links-console {
    flex-direction: column;
    align-items: flex-start;
    gap: 20px;
  }
}
```

- [ ] **Step 3c: Import the stylesheet**

In `assets/css/app.css`, directly below the existing `@import "./site.css" layer(components);` line, add:

```css
@import "./links.css" layer(components);
```

- [ ] **Step 4: Run tests to verify they pass**

Run: `mix test test/newton_web/controllers/links_controller_test.exs`
Expected: PASS (4 tests).

- [ ] **Step 5: Commit**

```bash
git add lib/newton_web/controllers/links_html/index.html.heex assets/css/links.css assets/css/app.css test/newton_web/controllers/links_controller_test.exs
git commit -m "Build the full /links takeover markup and scoped Gibson styling"
```

---

### Task 4: Add "Links" to the site nav (with Swup bypass)

**Files:**
- Modify: `lib/newton_web/components/site_components.ex` (the `site_nav/1` component)

**Why `data-no-swup`:** Swup swaps only `#main`, but the site header lives outside `#main`, so a Swup navigation into `/links` would leave the header visible and break the takeover. `data-no-swup` forces a full-document navigation. (Swup v4 honors `data-no-swup` on the anchor.)

- [ ] **Step 1: Add the nav entry**

In `lib/newton_web/components/site_components.ex`, inside `site_nav/1`, add a separator and a Links anchor after the Resume entry (still inside `<nav class="site-nav">`):

```heex
      <span class="site-nav-sep" aria-hidden="true">·</span>
      <a href="/links" data-no-swup>Links</a>
```

- [ ] **Step 2: Verify it compiles and the home page renders the nav entry**

Run: `mix test test/newton_web/controllers/page_controller_test.exs`
Expected: PASS (the existing home-page tests still pass; the nav now includes a Links link).

- [ ] **Step 3: Manual sanity check (optional)**

Start the server on the alternate port and confirm clicking **Links** performs a full navigation (no header bleed):
Run: `PORT=4001 mix phx.server` then visit `http://localhost:4001`.
Expected: the home page shows a `Links` nav item; clicking it loads `/links` with no site header.

- [ ] **Step 4: Commit**

```bash
git add lib/newton_web/components/site_components.ex
git commit -m "Add Links to the site nav, bypassing Swup for the takeover"
```

---

### Task 5: Wire the readout to hover/focus (vanilla JS)

**Files:**
- Create: `assets/js/links.js`
- Modify: `assets/js/app.js` (import + init, following the `initPhotos` pattern)
- Test: `assets/js/links.test.js`

- [ ] **Step 1: Write the failing test**

```javascript
// assets/js/links.test.js
import {describe, it, expect, beforeEach} from "vitest"
import {readoutFor, initLinks} from "./links"

function mountLinks() {
  document.body.innerHTML = `
    <main class="links">
      <ul class="links-menu">
        <li><a class="links-item" id="a1" href="https://github.com/jameswritescode"
               data-name="GITHUB" data-url="https://github.com/jameswritescode"
               data-desc="Code and source.">GITHUB</a></li>
        <li><a class="links-item" id="a2" href="https://markos.ai"
               data-name="MARK OS" data-url="https://markos.ai"
               data-desc="Where I work.">MARK OS</a></li>
      </ul>
      <aside class="links-readout">
        <div class="links-readout-name" data-readout="name">GITHUB</div>
        <div class="links-readout-url" data-readout="url">https://github.com/jameswritescode</div>
        <div class="links-readout-desc" data-readout="desc">Code and source.</div>
      </aside>
    </main>
  `
}

describe("links readout", () => {
  beforeEach(() => (document.body.innerHTML = ""))

  it("readoutFor reads the link's data attributes", () => {
    mountLinks()
    const r = readoutFor(document.getElementById("a2"))
    expect(r).toEqual({name: "MARK OS", url: "https://markos.ai", desc: "Where I work."})
  })

  it("updates the readout panel when an item is hovered", () => {
    mountLinks()
    initLinks()
    document.getElementById("a2").dispatchEvent(new Event("mouseenter"))
    expect(document.querySelector('[data-readout="name"]').textContent).toBe("MARK OS")
    expect(document.querySelector('[data-readout="url"]').textContent).toBe("https://markos.ai")
    expect(document.querySelector('[data-readout="desc"]').textContent).toBe("Where I work.")
  })

  it("updates the readout panel when an item receives focus", () => {
    mountLinks()
    initLinks()
    document.getElementById("a2").dispatchEvent(new Event("focus"))
    expect(document.querySelector('[data-readout="name"]').textContent).toBe("MARK OS")
  })

  it("no-ops when there is no links page", () => {
    document.body.innerHTML = `<main id="main"></main>`
    expect(() => initLinks()).not.toThrow()
  })
})
```

- [ ] **Step 2: Run test to verify it fails**

Run: `pnpm --dir assets test links`
Expected: FAIL — `./links` module does not exist.

- [ ] **Step 3: Implement the module**

```javascript
// assets/js/links.js
// Drives the /links readout panel from the hovered/focused menu item.
// Pure-DOM, no dependencies. Safe to call on any page (no-ops off /links).

export function readoutFor(el) {
  return {name: el.dataset.name, url: el.dataset.url, desc: el.dataset.desc}
}

export function initLinks() {
  const root = document.querySelector("main.links")
  if (!root) return

  const out = {
    name: root.querySelector('[data-readout="name"]'),
    url: root.querySelector('[data-readout="url"]'),
    desc: root.querySelector('[data-readout="desc"]'),
  }
  if (!out.name || !out.url || !out.desc) return

  root.querySelectorAll(".links-item").forEach((item) => {
    const update = () => {
      const r = readoutFor(item)
      out.name.textContent = r.name
      out.url.textContent = r.url
      out.desc.textContent = r.desc
    }
    item.addEventListener("mouseenter", update)
    item.addEventListener("focus", update)
  })
}
```

- [ ] **Step 4: Run test to verify it passes**

Run: `pnpm --dir assets test links`
Expected: PASS (4 tests).

- [ ] **Step 5: Wire it into the app bundle**

In `assets/js/app.js`, add the import alongside the other page-specific imports (near `import {initPhotos, teardownPhotos} from "./photos"`):

```javascript
import {initLinks} from "./links"
```

Then call it where the page-specific init already runs. Update the existing `content:replace` Swup hook and the initial-load call so both also run `initLinks()`:

```javascript
swup.hooks.on("content:replace", () => {
  initPhotos()
  initLinks()
  // Move focus into the new content and announce the page change to AT.
  // (Focusing the target also scrolls it into view, covering hash links.)
  focusAfterNavigation()
})
// Initial page load (Swup doesn't fire content:replace for the first page).
initPhotos()
initLinks()
scrollToHash()
```

(`/links` itself is reached via full navigation, so the initial-load call is what runs there; the `content:replace` call covers any future in-app routing.)

- [ ] **Step 6: Run the full JS suite + build to confirm nothing broke**

Run: `pnpm --dir assets test`
Expected: PASS (all suites, including the new `links` suite).

- [ ] **Step 7: Commit**

```bash
git add assets/js/links.js assets/js/links.test.js assets/js/app.js
git commit -m "Wire the /links readout panel to hover and focus"
```

---

### Final verification

- [ ] **Run the full Elixir suite**

Run: `mix test`
Expected: PASS (including `Newton.LinksTest` and `NewtonWeb.LinksControllerTest`).

- [ ] **Run the full JS suite**

Run: `pnpm --dir assets test`
Expected: PASS (including `links.test.js`).

- [ ] **Run precommit**

Run: `mix precommit`
Expected: clean (format, compile with warnings-as-errors, tests).

---

## What Phase A delivers

A working, accessible `/links` page: full-screen Gibson takeover, real outbound links as a chunky neon menu, a readout panel that tracks the hovered/focused item (and is correct without JS), keyboard-navigable, reachable from the site nav via a full-document navigation that preserves the takeover.

## Deferred to later phases (NOT in this plan)

- **Phase B:** the mosaic pixel page-transition (main site → /links).
- **Phase C:** the three.js cinematic fly-through, its first-visit-only gating, reduced-motion/no-WebGL handling, and three.js bundle delivery.
- Building the actual RSS feed; the blogroll section.
