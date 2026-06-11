# Admin Milkdown Editor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the post editor's markdown textarea with Milkdown (Crepe) — a live, inline rich-markdown editor — while keeping `body_markdown` canonical and MDEx the sole renderer of the published page.

**Architecture:** Milkdown is heavy, so the admin gets its **own esbuild entry point** (`admin.js` + its CSS), loaded only by the admin root layout; the public `app.js` is untouched (this keeps the public bundle lean — the spec's goal — without migrating the shared bundle to ESM/code-splitting). A LiveView JS hook mounts a Crepe editor over a `phx-update="ignore"` container, seeds it from the post's markdown, and writes every change back into a hidden `post[body_markdown]` input so the existing form/save path is unchanged. MDEx still renders `body_html` on save.

**Tech Stack:** Phoenix 1.8 LiveView, esbuild (multi-entry), pnpm, `@milkdown/crepe` + `@milkdown/plugin-listener`, Vitest, the existing `Newton.Blog` + `PostLive.Editor`.

**Scope note:** Plan 3 of the admin series. Plan 1 = foundation, Plan 2 = Posts (textarea editor + drawer + draft visibility). This plan swaps only the body editor. Spec: `docs/superpowers/specs/2026-06-10-admin-dashboard-design.md`.

**Version caveat:** Milkdown's exact API is version-specific. The hook code targets `@milkdown/crepe` v7.x (`new Crepe({root, defaultValue})`, `crepe.create()`, `crepe.getMarkdown()`, `crepe.destroy()`, listener via `@milkdown/plugin-listener`). Confirm method names against the installed version's types; the tests and browser smoke lock the required *behavior* (markdown round-trips through a hidden input on save).

---

## File Structure

**Authored / modified:**
- Modify: `config/config.exs` — add `admin.js` to the esbuild entry args
- Create: `assets/js/admin.js` — the admin bundle: LiveSocket + `AdminTheme` + `MilkdownEditor` hooks + Crepe theme CSS import
- Modify: `assets/js/app.js` — remove the admin-only `AdminTheme` hook (now in `admin.js`)
- Modify: `lib/newton_web/components/layouts/admin_root.html.heex` — load `admin.js` (+ its CSS) instead of `app.js`
- Create: `assets/js/hooks/milkdown_editor.js` — the editor hook + the testable `syncMarkdown` glue
- Create: `assets/js/hooks/milkdown_editor.test.js` — Vitest for the glue
- Modify: `assets/package.json` (via pnpm) — Milkdown deps
- Modify: `lib/newton_web/live/admin/post_live/editor.ex` — swap the body textarea for the Milkdown container + hidden input
- Modify: `assets/css/admin.css` — neutral theme overrides for the Crepe editor surface
- Test: `test/newton_web/live/admin/post_editor_live_test.exs` — form contract still holds

---

## Task 1: Give the admin its own JS bundle

Move the admin onto a dedicated `admin.js` entry so Milkdown (added next) never touches the public `app.js`.

**Files:**
- Modify: `config/config.exs`
- Create: `assets/js/admin.js`
- Modify: `assets/js/app.js`
- Modify: `lib/newton_web/components/layouts/admin_root.html.heex`

- [ ] **Step 1: Add `admin.js` to the esbuild entry args**

In `config/config.exs`, change the esbuild `:newton` args to build both entries:

```elixir
config :esbuild,
  version: "0.25.4",
  newton: [
    args:
      ~w(js/app.js js/admin.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]
```

- [ ] **Step 2: Create the admin bundle**

Create `assets/js/admin.js`:

```javascript
// The admin bundle, loaded only by the admin root layout. Kept separate from
// the public app.js so the heavy Milkdown editor (added in this plan) never
// ships to public visitors. Sets up its own LiveSocket with the admin hooks.
import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"
import {hooks as colocatedHooks} from "phoenix-colocated/newton"
import topbar from "../vendor/topbar"
import {AdminTheme} from "./hooks/admin_theme"

const csrfToken = document.querySelector("meta[name='csrf-token']").getAttribute("content")
const liveSocket = new LiveSocket("/live", Socket, {
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken},
  hooks: {...colocatedHooks, AdminTheme},
})

topbar.config({barColors: {0: "#29d"}, shadowColor: "rgba(0, 0, 0, .3)"})
window.addEventListener("phx:page-loading-start", _info => topbar.show(300))
window.addEventListener("phx:page-loading-stop", _info => topbar.hide())

liveSocket.connect()
window.liveSocket = liveSocket
```

- [ ] **Step 3: Remove the admin hook from the public bundle**

In `assets/js/app.js`, delete the `AdminTheme` import and its entry in the hooks object:

- Remove the line `import {AdminTheme} from "./hooks/admin_theme"`.
- Change `hooks: {...colocatedHooks, RippleCanvas, AdminTheme},` to `hooks: {...colocatedHooks, RippleCanvas},`.

- [ ] **Step 4: Point the admin layout at the admin bundle**

In `lib/newton_web/components/layouts/admin_root.html.heex`, replace the `app.js` script tag with `admin.js` and add its CSS (esbuild emits `admin.css` next to it once Task 2 imports a stylesheet; harmless to reference now):

```heex
    <link phx-track-static rel="stylesheet" href={~p"/assets/css/app.css"} />
    <link phx-track-static rel="stylesheet" href={~p"/assets/js/admin.css"} />
    <script defer phx-track-static type="text/javascript" src={~p"/assets/js/admin.js"}>
    </script>
```

> Keep the existing `app.css` link (the admin needs the Tailwind tokens/utilities). The new `admin.css` is the esbuild-emitted Crepe theme (created in Task 2). Until Task 2 imports CSS, `admin.css` won't exist — if a missing-asset 404 in dev is noisy, add the `<link>` in Task 2 instead. The `~p` verified-route check does not apply to these string-built static paths.

- [ ] **Step 5: Build and verify both bundles exist**

Run: `mix assets.build`
Expected: succeeds; `priv/static/assets/js/app.js` and `priv/static/assets/js/admin.js` both exist (`ls priv/static/assets/js`).

- [ ] **Step 6: Verify the public JS tests still pass**

Run: `mix cmd --cd assets pnpm test`
Expected: PASS (the `admin_theme` test imports the hook module directly and is unaffected).

- [ ] **Step 7: Commit**

```bash
git add config/config.exs assets/js/admin.js assets/js/app.js lib/newton_web/components/layouts/admin_root.html.heex
git commit -m "Give the admin its own JS bundle (admin.js)"
```

---

## Task 2: Install Milkdown and wire its theme

**Files:**
- Modify: `assets/package.json`, `assets/pnpm-lock.yaml` (via pnpm)
- Modify: `assets/js/admin.js`

- [ ] **Step 1: Install Milkdown (pnpm, not npm)**

Run from the repo root:

```bash
mix cmd --cd assets pnpm add @milkdown/crepe @milkdown/plugin-listener
```

Expected: `@milkdown/crepe` and `@milkdown/plugin-listener` (plus transitive deps) added under `assets/node_modules`; `package.json` gains a `dependencies` block.

- [ ] **Step 2: Import the Crepe theme into the admin bundle**

In `assets/js/admin.js`, add near the top (after the existing imports):

```javascript
// Crepe's base styles + a frame theme. esbuild extracts these into admin.css.
import "@milkdown/crepe/theme/common/style.css"
import "@milkdown/crepe/theme/frame.css"
```

- [ ] **Step 3: Build and confirm esbuild emits admin.css**

Run: `mix assets.build`
Expected: succeeds; `priv/static/assets/js/admin.css` now exists (`ls priv/static/assets/js/admin.css`). If the theme path differs in the installed version, list `assets/node_modules/@milkdown/crepe/theme` and use the actual `common` + a frame stylesheet.

- [ ] **Step 4: Commit**

```bash
git add assets/package.json assets/pnpm-lock.yaml assets/js/admin.js
git commit -m "Add Milkdown (Crepe) to the admin bundle"
```

---

## Task 3: The MilkdownEditor hook

The hook mounts a Crepe editor and mirrors its markdown into a hidden input so the existing form save path is unchanged. The DOM-sync glue is a separate, testable function; the Crepe lifecycle is browser-verified (ProseMirror doesn't run under jsdom).

**Files:**
- Create: `assets/js/hooks/milkdown_editor.js`
- Test: `assets/js/hooks/milkdown_editor.test.js`

- [ ] **Step 1: Write the failing test for the sync glue**

Create `assets/js/hooks/milkdown_editor.test.js`:

```javascript
import {describe, it, expect, vi} from "vitest"
import {syncMarkdown} from "./milkdown_editor"

describe("syncMarkdown", () => {
  it("writes the markdown to the input and dispatches an input event", () => {
    const input = document.createElement("input")
    const handler = vi.fn()
    input.addEventListener("input", handler)

    syncMarkdown(input, "# Hello\n\nbody")

    expect(input.value).toBe("# Hello\n\nbody")
    expect(handler).toHaveBeenCalledTimes(1)
  })

  it("does not dispatch when the value is unchanged", () => {
    const input = document.createElement("input")
    input.value = "same"
    const handler = vi.fn()
    input.addEventListener("input", handler)

    syncMarkdown(input, "same")

    expect(handler).not.toHaveBeenCalled()
  })
})
```

- [ ] **Step 2: Run to confirm failure**

Run: `mix cmd --cd assets pnpm test`
Expected: FAIL — `syncMarkdown` not exported.

- [ ] **Step 3: Implement the hook + glue**

Create `assets/js/hooks/milkdown_editor.js`:

```javascript
import {Crepe} from "@milkdown/crepe"
import {listener, listenerCtx} from "@milkdown/plugin-listener"

// Mirror markdown into the hidden form input and notify LiveView, but only when
// it actually changed (so we don't spam phx-change or loop on our own writes).
export function syncMarkdown(input, markdown) {
  if (input.value === markdown) return
  input.value = markdown
  input.dispatchEvent(new Event("input", {bubbles: true}))
}

// phx-hook on a container that also holds a hidden `post[body_markdown]` input.
// The container must be wrapped in phx-update="ignore" so LiveView never patches
// the editor's DOM after mount.
export const MilkdownEditor = {
  async mounted() {
    const input = document.getElementById(this.el.dataset.inputId)
    const initial = input ? input.value : ""

    this.crepe = new Crepe({root: this.el, defaultValue: initial})
    this.crepe.editor.use(listener)
    this.crepe.editor.config((ctx) => {
      ctx.get(listenerCtx).markdownUpdated((_ctx, markdown) => {
        if (input) syncMarkdown(input, markdown)
      })
    })

    await this.crepe.create()
  },

  destroyed() {
    this.crepe?.destroy()
  },
}
```

- [ ] **Step 4: Run to confirm the glue test passes**

Run: `mix cmd --cd assets pnpm test`
Expected: PASS (the `syncMarkdown` tests pass; importing `@milkdown/crepe` at the top is fine under jsdom as long as no test instantiates `Crepe`).

> If importing `@milkdown/crepe` makes Vitest fail to load the module under jsdom, move the `Crepe`/`listener` imports to a dynamic `import()` at the top of `mounted()` so the module is only loaded in the browser, keeping `syncMarkdown` import-safe for the test.

- [ ] **Step 5: Register the hook in the admin bundle**

In `assets/js/admin.js`, import and register the hook:

```javascript
import {MilkdownEditor} from "./hooks/milkdown_editor"
```

and change the hooks to `hooks: {...colocatedHooks, AdminTheme, MilkdownEditor},`.

- [ ] **Step 6: Build to confirm it bundles**

Run: `mix assets.build`
Expected: succeeds (Milkdown is bundled into `admin.js`).

- [ ] **Step 7: Commit**

```bash
git add assets/js/hooks/milkdown_editor.js assets/js/hooks/milkdown_editor.test.js assets/js/admin.js
git commit -m "Add the MilkdownEditor hook and its sync glue"
```

---

## Task 4: Swap the textarea for Milkdown in the editor

**Files:**
- Modify: `lib/newton_web/live/admin/post_live/editor.ex`
- Test: `test/newton_web/live/admin/post_editor_live_test.exs`

- [ ] **Step 1: Write the failing test for the editor markup contract**

Append to `test/newton_web/live/admin/post_editor_live_test.exs`:

```elixir
  test "the editor renders a Milkdown container seeded from the post body", %{conn: conn} do
    {:ok, post} =
      Newton.Blog.create_post(%{title: "MD", slug: "md", body_markdown: "# Seeded body"})

    {:ok, view, _html} = live(conn, ~p"/admin/posts/#{post.id}/edit")

    assert has_element?(view, "#milkdown-editor[phx-hook='MilkdownEditor']")
    assert has_element?(view, "input#post_body_markdown[type='hidden']")
    assert render(view) =~ "# Seeded body"
  end
```

- [ ] **Step 2: Run to confirm failure**

Run: `mix test test/newton_web/live/admin/post_editor_live_test.exs:NN` (the new test's line)
Expected: FAIL — the textarea is still present, no `#milkdown-editor`.

- [ ] **Step 3: Replace the body textarea**

In `lib/newton_web/live/admin/post_live/editor.ex`, replace the `<.input field={@form[:body_markdown]} type="textarea" ...>` block with the Milkdown container + a hidden input, wrapped in a `phx-update="ignore"` region:

```heex
        <div id="body-editor" phx-update="ignore">
          <input
            type="hidden"
            name="post[body_markdown]"
            id="post_body_markdown"
            value={Phoenix.HTML.Form.normalize_value("text", @form[:body_markdown].value)}
          />
          <div
            id="milkdown-editor"
            phx-hook="MilkdownEditor"
            data-input-id="post_body_markdown"
            class="rounded-lg border border-(--admin-border) bg-(--admin-surface)"
          >
          </div>
        </div>
```

> `phx-update="ignore"` keeps LiveView from re-rendering the editor/hidden input after mount, so the hook fully owns them. The hidden input still submits with the form and its `input` events drive `phx-change="validate"`. The initial markdown reaches the hook via the hidden input's `value` (read in `mounted()`), and appears in the rendered HTML (the test asserts the seeded body is present).

- [ ] **Step 4: Run to confirm pass**

Run: `mix test test/newton_web/live/admin/post_editor_live_test.exs`
Expected: PASS — all editor tests (the create/edit/publish/delete tests still submit `post[body_markdown]` via the form helper, which sets the hidden input).

- [ ] **Step 5: Commit**

```bash
git add lib/newton_web/live/admin/post_live/editor.ex test/newton_web/live/admin/post_editor_live_test.exs
git commit -m "Render the Milkdown editor in place of the body textarea"
```

---

## Task 5: Theme the editor surface (neutral admin colors)

Crepe ships its own theme; tone it to the admin palette so it reads as part of the admin, not a foreign widget.

**Files:**
- Modify: `assets/css/admin.css`

- [ ] **Step 1: Add neutral overrides for the Crepe surface**

Append to `assets/css/admin.css` (these target Crepe's editor container; class names are stable `milkdown`/`ProseMirror` hooks, but verify against the rendered DOM in the browser smoke and adjust selectors if the installed theme differs):

```css
/* Tone the Milkdown (Crepe) editor to the admin palette. */
#milkdown-editor .milkdown {
  background: var(--admin-surface);
  color: var(--admin-text);
}

#milkdown-editor .ProseMirror {
  min-height: 24rem;
  padding: 1.25rem 1.5rem;
  font-family: ui-sans-serif, system-ui, -apple-system, sans-serif;
}

#milkdown-editor .ProseMirror:focus {
  outline: none;
}

#milkdown-editor .ProseMirror a {
  color: var(--admin-accent);
}
```

- [ ] **Step 2: Build**

Run: `mix assets.build`
Expected: succeeds.

- [ ] **Step 3: Commit**

```bash
git add assets/css/admin.css
git commit -m "Tone the Milkdown editor to the admin palette"
```

---

## Task 6: Precommit + browser smoke

The Crepe editor is browser-only; this task is where its real behavior is verified.

**Files:** none (verification).

- [ ] **Step 1: Run precommit**

Run: `mix precommit`
Expected: PASS — compile (warnings-as-errors), formatter, `credo --strict`, both test suites, dialyzer. Fix any findings.

- [ ] **Step 2: Browser smoke (dev)**

Start the server (`mix phx.server`), sign in, then:
- Open `/admin/posts/new`. The body area renders the **Milkdown editor** (not a textarea). Type `## A heading` and press space → it becomes a real heading inline. Type `- item` → a bullet. Type `**bold**` → bold.
- Set a title (slug auto-fills), then Save. Confirm you stay on the edit URL and the status badge updates.
- Reload the edit page → the editor is **seeded** with the previously saved markdown.
- Open an existing post's editor → its body renders in Milkdown.
- "View on site ↗" → the published page renders the **MDEx** output of that markdown (the source of truth), confirming the round-trip.
- Visit a public page (e.g. `/`) and confirm the network panel does **not** load `admin.js`/Milkdown (the public bundle stayed lean).

- [ ] **Step 3: Final commit if precommit required fixes**

```bash
git add -A
git commit -m "Address precommit findings for the Milkdown editor"
```

---

## Self-Review Notes

- **Spec coverage:** single focused Milkdown (Crepe + GFM) editor with inline rendering (Tasks 2–4) ✓; `body_markdown` canonical, MDEx renders on save (unchanged save path; Task 4 keeps the hidden `post[body_markdown]` field) ✓; runs as a `phx-hook` with `phx-update="ignore"` (Task 4) ✓; lazy-loaded off the public bundle (Task 1 — via a separate `admin.js` entry rather than the spec's "dynamic import"; **same goal, simpler mechanism — update the spec's build note**) ✓; neutral admin colors with editor styling (Task 5) ✓; "View on site" preview already shipped in Plan 2 and verified here (Task 6) ✓. **Deferred:** deep published-typography fidelity (Lora, exact heading scale) and matching the site's Lumis code-highlight palette inside the editor — Task 5 does neutral toning; pixel-matching the public prose is a follow-up polish iteration. GFM coverage rides on Crepe's bundled GFM preset (verified by typing a table/task-list in the smoke).
- **Type/contract consistency:** the hidden input id `post_body_markdown` is referenced by the hook via `data-input-id` (Task 4) and read in `mounted()` (Task 3); `syncMarkdown(input, markdown)` signature matches between the hook, the glue, and the test. The form field name stays `post[body_markdown]`, so all Plan 2 editor tests (create/edit/publish/delete) keep passing unchanged.
- **Placeholder scan:** no TBD/TODO; every code step has full code. The two "if the version differs" notes give concrete fallbacks (dynamic import for test-safety; theme path/selector verification), not missing content.
- **Risk:** Milkdown's API and theme class names are version-specific and the editor is browser-only — hence the glue is unit-tested, the form contract is LiveView-tested, and the actual editor is browser-smoked. If Crepe's API differs materially from v7.x, adjust the hook's `mounted()` to the installed version while keeping the `syncMarkdown` contract.
```
