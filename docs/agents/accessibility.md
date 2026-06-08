# Accessibility auditor

Use when auditing this site for accessibility — whether triggered by a code change that touches UI, a new page, or a standalone request like "do an a11y audit."

## Purpose

Produce a tiered, actionable audit. Match the site's voice: specific, not boilerplate. The reader already knows what ARIA is — tell them what's wrong *here*, where, and why it matters.

## Scope

Target WCAG 2.2 AA as the baseline. Go past it when the fix is cheap and the improvement is real. Don't stop at markup — check keyboard operability, focus management, color contrast (most tier-shift on this site is now via pre-mixed color tokens, but a few surfaces still use opacity), reduced-motion, and the accessibility tree: landmarks, labels, live regions.

## Approach

1. Read every page you're auditing, not just `styles.css`. Accessibility lives in the HTML.
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

- **`ripple.js` canvas is purely decorative.** `aria-hidden="true"` is correct; don't recommend adding labels or roles.
- **Dark mode contrast is high (~12.9:1).** Light mode is the palette that usually needs attention. Audit both, but expect findings to cluster on light.
- **Tier-shift is mostly via pre-mixed color tokens, not opacity.** `--text-subdued` and `--text-muted` are designed to clear 4.5:1 against `--bg` in both palettes; if a label/meta/byline fails contrast, fix the token in `:root` or `:root.dark`, not per-rule. The remaining opacity surface is `--opacity-dim: 0.93` and the `0.6` badge fade on `.post-body pre::before`.
- **The `--syntax-*` family** (`--syntax-keyword`, `--syntax-amber`, `--syntax-rose`) is part of the audit surface inside `<pre>` blocks. All three pass 4.5:1 against `--bg` in both palettes by design — verify if you change any of them.
- **View transitions are cross-document** via `@view-transition: navigation: auto`. `prefers-reduced-motion` should disable them; verify that still holds after changes.
- **The photo lightbox is a custom `<div>` with `role="dialog"` and `aria-modal="true"`.** Audit it as a modal: focus trap, Esc, scroll lock, focus restore, `inert` when closed.
- **The photo grid is script-rendered** into `.photo-column` divs. Images stay in the DOM across relayout — event handlers persist. Don't flag DOM replacement as breaking listeners without checking.
- **No client-side routing.** Every navigation is a real page load, so there are no focus-restore-after-route problems to worry about.

## Contrast math, quickly

The two palettes in `styles.css`:

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
