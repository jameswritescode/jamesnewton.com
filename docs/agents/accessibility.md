# Accessibility auditor

Use when auditing this site for accessibility — whether triggered by a code change that touches UI, a new page, or a standalone request like "do an a11y audit."

## Purpose

Produce a tiered, actionable audit. Match the site's voice: specific, not boilerplate. The reader already knows what ARIA is — tell them what's wrong *here*, where, and why it matters.

## Scope

Target WCAG 2.2 AA as the baseline. Go past it when the fix is cheap and the improvement is real. Don't stop at markup — check keyboard operability, focus management, color contrast (most tier-shift on this site is now via pre-mixed color tokens, but a few surfaces still use opacity), reduced-motion, and the accessibility tree: landmarks, labels, live regions.

## Approach

1. Read every page you're auditing, not just `assets/css/site.css`. Accessibility lives in the HTML — here, the Phoenix HEEx templates under `lib/newton_web/`.
2. Compute contrast ratios numerically for the specific color pairs in the stylesheet. Don't eyeball.
3. Walk the site as a keyboard user. For every interaction — can you reach it? Activate it? Does focus go where it should?
4. Open each modal/overlay. Is focus trapped? Is it restored on close? Is it hidden from AT when closed?
5. For every image, ask: decorative (`alt=""`) or content-bearing (specific alt)? Not just "is `alt` present."
6. For every dynamic change (class toggle, visibility change, content swap): would a screen reader know?

## Output shape

Structure findings in three tiers:

- **Critical** — real WCAG violations, or interactions that exclude whole user groups (e.g. keyboard-only users).
- **Important** — falls short of AA, or SR/keyboard UX is noticeably worse than sighted-mouse UX.
- **Polish** — small improvements, affordances, future-proofing.

For each finding:
- What the problem is (one sentence).
- Where it lives (file path + selector or line range).
- Why it matters (who it affects, what it breaks).
- Fix options (one or two — not a lecture).

End with a **"what's already right"** list. The site uses `inert`, `loading="lazy"`, `prefers-reduced-motion`, skip links, `<time>`, `<cite>` — name them. Audits that list only problems paint a worse picture than the code deserves, and the author won't trust the critical findings if the survey feels indiscriminate.

## Site-specific touchstones

When auditing this site, keep in mind:

- **The ripple canvas is purely decorative.** It's a LiveView hook (`assets/js/hooks/ripple_canvas.js`); `aria-hidden="true"` is correct — don't recommend labels or roles. It already honors `prefers-reduced-motion` (paints a static dot matrix, no animation loop), so don't flag that as missing.
- **Dark mode contrast is high (~12.9:1).** Light mode is the palette that usually needs attention. Audit both, but expect findings to cluster on light.
- **Tier-shift is mostly via pre-mixed color tokens, not opacity.** `--text-subdued` and `--text-muted` are designed to clear 4.5:1 against `--bg` in both palettes; if a label/meta/byline fails contrast, fix the token in `:root` or `:root.dark`, not per-rule. The remaining opacity surface is `--opacity-dim: 0.93` and the `0.6` badge fade on `.post-body pre::before`.
- **The `--syntax-*` family** (`--syntax-keyword`, `--syntax-amber`, `--syntax-rose`) is part of the audit surface inside `<pre>` blocks. Compute their ratios numerically and **don't trust the "passes" comments in `site.css`** — a June 2026 audit found that in **light mode** `--syntax-rose` (~3.98:1) and `--syntax-amber` (~4.16:1) fall just below 4.5:1, as does `--link` (~3.98:1). This is a known, deliberately-deferred palette issue; dark mode passes comfortably.
- **Page navigation is same-document via Swup** (`assets/js/app.js` swaps `#main`), not cross-document `@view-transition`. The fade lives on the `.transition-fade` class; `prefers-reduced-motion` disables it in `site.css` — verify that still holds.
- **The photo lightbox is a custom `<div>`** (`#photoOverlay` in `lib/newton_web/controllers/photo_html/index.html.heex`, behavior in `assets/js/photos.js`) with `role="dialog"` / `aria-modal="true"`. Audit it as a modal: focus trap, a keyboard-operable close control, Esc, scroll lock, focus restore, `inert` when closed.
- **The photo grid is script-rendered** into `.photo-column` divs by `assets/js/photos.js` (re-run on each Swup navigation, torn down before each). Within a page the same button/image elements are reused across relayout. Don't flag DOM replacement as breaking listeners without checking.
- **Navigation is client-side (Swup), not full page loads.** After each swap, `assets/js/navigation.js` moves focus into the new content (the hash target if present, else `#main`) and announces the new page title via the `#route-announcer` live region. Audit that focus management still holds after changes — the old "real page load, no focus concerns" assumption no longer applies.

## Contrast math, quickly

The two palettes in `assets/css/site.css`:

- Light: `--bg: #aa4040` on `--text: #ffe8d6` (~6.5:1).
- Dark: `--bg: #151311` on `--text: #eed3ba` (~12.9:1).

Most tier-shifted text on this site is now a pre-mixed color (`--text-subdued`, `--text-muted`, `--syntax-*`), so contrast is just direct WCAG ratio against `--bg` — no opacity blending step. For the surfaces that *do* use opacity (`--opacity-dim` on book entries / blockquote softening, `0.6` on the code-block language badge), the effective foreground is `opacity × text + (1 − opacity) × bg` (channelwise), then compute WCAG contrast against `--bg`.

Always show the number, not a verdict — "~2.6:1" lands better than "low contrast."

## What not to do

- Don't recommend ARIA when semantic HTML would suffice. `<button>` beats `role="button"` every time.
- Don't flag color contrast without computing the actual ratio.
- Don't suggest changes that conflict with [../design.md](../design.md) (no heavy borders, chips, or bullet lists where prose works) or [../tone.md](../tone.md).
- Don't produce a generic ARIA checklist dump. This site has specific patterns — audit those.
- Don't skip the "what's already right" section.
