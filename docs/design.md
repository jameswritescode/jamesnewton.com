# Design

The site aims for a warm, literary feel — Lora serif on a cream-on-warm palette, everything text-forward. No chrome, no UI chips, no borders unless they're earning their place. Typography carries the weight.

> **Keep this doc honest.** When a design decision changes (palette, type, weights, tokens, treatments), update this doc as part of the same change. Don't let it drift behind the stylesheet.

## Color tokens

All colors live as CSS custom properties on `:root`. The light palette is the default. The dark palette is defined once as `--*-dark` variables; both the `@media (prefers-color-scheme: dark) :root:not(.light)` rule and the `:root.dark` rule remap the public tokens (`--bg`, `--text`, …) to those shared dark values. This means there's one source of truth for dark colors — the two triggers can't drift.

**Light mode** (warm cream on terracotta):
```
--bg: #aa4040;
--text: #ffe8d6;
--text-subdued: #fde4ca;      /* body-adjacent, slightly dimmed — passes 4.5:1 */
--text-muted: #fce0c3;        /* labels, meta, dates — passes 4.5:1 */
--link: #ffc89c;
--strong: #fff5e8;
--syntax-keyword: #fff0c8;    /* code keywords — passes 6.3:1 */
--syntax-amber: #ffd089;      /* code numbers / literals — passes 4.7:1 */
--syntax-rose: #ffc6b5;       /* code types / function names — passes 4.5:1 */
--dot: 255, 232, 214;         /* RGB tuple for canvas rgba() */
--dot-base-opacity: 0.06;
--ripple-peak-opacity: 0.3;
--feed-hover: rgba(255, 232, 214, 0.08);
```

**Dark mode** (soft cream on near-black):
```
--bg: #151311;
--text: #eed3ba;
--text-subdued: #c3ac98;
--text-muted: #ad9987;
--link: #e8a87c;
--strong: #f5e4cc;
--syntax-keyword: #f5dfa8;
--syntax-amber: #d9b577;
--syntax-rose: #d4988a;
--dot: 238, 211, 186;
--dot-base-opacity: 0.04;
--ripple-peak-opacity: 0.3;
--feed-hover: rgba(238, 211, 186, 0.06);
```

**Naming logic**:
- `--bg` / `--text` are the foundation pair.
- `--text-subdued` and `--text-muted` are pre-mixed dimmer cream values for body-adjacent prose and label-tier copy. They replace opacity blends so contrast stays predictable across both palettes (every tier passes 4.5:1).
- `--link` is a hue-shifted accent — warmer than text, never a different color family.
- `--strong` is the text color lifted slightly. Stays in the cream family; never a new hue.
- `--syntax-keyword` / `--syntax-amber` / `--syntax-rose` form the code-block accent family: a buttery yellow for structural tokens (keywords, decorators), a warmer amber for numeric data, and a salmon-pink for named entities (types, function names). All three live in the warm gradient — no cool tones in code highlighting.
- `--dot` is an RGB tuple (not a full color) so it can compose into `rgba(var(--dot), 0.08)` for canvas and subtle borders/backgrounds.
- `--feed-hover` is a single-use alpha tint for the feed item background on hover.

## Typography

- **Body**: Lora (loaded from Google Fonts as a variable font), with `Georgia, "Times New Roman", serif` as fallback. 1.1rem base, 1.8 line-height. Lora was chosen over Georgia specifically so `<strong>` can render at a real semi-bold (600) face rather than resolving up to Georgia's 700.
- **Code**: `ui-monospace, "SF Mono", Menlo, Consolas, monospace`. 0.92em inline, 0.9rem in blocks.
- **Weight**: headings use `font-weight: normal` (color and size carry emphasis, not weight). The one explicit weight bump is the global `strong { font-weight: 600; color: var(--strong); }` rule — applies sitewide, not just to posts.

**Size ladder** (approximate, largest to smallest):

| Element | Size |
|---|---|
| `.post-title`, `.intro-heading` | 2.4rem |
| `.post-body h2` | 1.6rem |
| `.site-name`, `.feed-item-title` | 1.4rem |
| `.resume-job-company` | 1.3rem |
| Body, `.feed-item-book` | 1.1rem / 1.05rem |
| `.feed-item-caption`, `.feed-item-excerpt` | 0.95rem |
| `.post-byline`, `.resume-job-meta`, `.feed-item-date` | 0.9rem / 0.85rem |
| `.feed-item-caption` when truly small | 0.85rem |
| Code badges | 0.7–0.75rem |

## Links

```css
a {
  color: var(--link);
  text-decoration: underline;
  text-decoration-thickness: 0.1em;
  text-underline-offset: 0.2em;
  transition: opacity 0.3s ease;
}
a:hover { opacity: 0.85; }
```

The thin underline + offset is the signature. Don't raise it to default browser thickness.

Unstyled "navigational" links (`.site-name`, `.site-nav a`, `.feed-item`) drop the underline but keep the opacity transition.

## Layout

All layout values live as tokens on `:root` so a single change propagates:

- `--container-width: 720px` — default content width.
- `--container-width-wide: 1040px` — used only by the photos page (activated via `body:has(.post.photos)`).
- `--container-pad-x: 24px`, `--container-pad-top: 40px`, `--container-pad-bottom: 80px`.
- **Radii**: `--radius-sm: 4px` (inline code), `--radius-md: 6px` (images), `--radius-lg: 8px` (feed items, code blocks).
- **Motion**: `--dur-fast: 0.22s` (lightbox), `--dur-default: 0.3s` (hover, page transitions).
- **z-index rule**: every content block sits at `z-index: 1` with `position: relative` so it renders above the fixed ripple canvas (`z-index: 0`).

## Opacity scale

Most tier-shift work has moved off opacity blends and onto pre-mixed color tokens (`--text-subdued`, `--text-muted`) so contrast is predictable across both palettes. The one remaining opacity token is:

- `--opacity-dim: 0.93` — body-ish prose slightly pulled back (link hover, book entries, blockquote softening).

The code-block language badge (`.post-body pre::before`) sits at `0.6` — a deliberate decorative fade. Anything dimmer than `--opacity-dim` should be questioned: if the goal is "less prominent," prefer reaching for `--text-subdued` or `--text-muted` instead.

## Letter-spacing

- `0.015em` on `body` — applied globally to give Lora a little extra air; reset to `normal` on `code, pre, kbd, samp` so monospace stays unaffected. Adopted when switching from Georgia to Lora, since Lora reads slightly tighter at the same size.
- `--label-tracking: 0.08em` — the shared value for uppercase labels (feed heading, site nav, table headers).
- `0.02em` on `.site-name` — subtle signature refinement, kept out of the token set.
- `0.1em` on code-block language badges — deliberately tighter than body labels.

## Component language

The hard rule: **prose is the default, components are the exception**. If a piece of content can be a sentence, make it a sentence. If it can be a paragraph, make it a paragraph.

Things we avoid:
- Chips, pills, badges (we tried tech-stack chips on the resume and removed them — they broke the typographic voice).
- Heavy borders, boxes, card outlines (use `--feed-hover` alpha tints for state changes instead).
- Bullet lists when a sentence works. Lists are for genuinely enumerable things, not for breaking up a paragraph.

Things we reach for:
- **Section labels**: uppercase, 0.08em letter-spacing, 1rem, opacity 0.6. Used for `.feed-heading`, `.site-nav`, `pre::before` language labels.
- **Meta lines**: 0.9rem, opacity 0.7, middot (`·`) separators. Used for `.post-byline`, `.resume-job-meta`, `.feed-item-date`.
- **Hover state**: background tint via `--feed-hover` at 8px border-radius on clickable blocks.

## Punctuation

- **Em dash (—) with spaces** for date ranges: `2021 — 2025`, `2025 — Present`.
- **Em dash with spaces** for prose asides, same as essayistic writing: `that's the craft — the tools, the trade-offs, and the quiet decisions`.
- **Middot (·)** for list separators in meta lines: `April 17, 2026 · 6 min read`.
- **Ampersand** only inside multi-word labels like "Flow & TypeScript", not as generic prose connector.

## Spacing & rhythm

- **Page-header to first content**: 2rem (32px). `.post-title` carries `margin-bottom: 2rem`. Pages whose first content is an `<h2>` inside `.post-body` (e.g. resume's "What I'm doing") have `.post-body > h2:first-child { margin-top: 0 }` so the h2's margin-top doesn't margin-collapse through the section and inflate the gap.
- **Paragraphs**: `margin-bottom: 1.5rem`.
- **H2**: `margin-top: 2.5rem; margin-bottom: 1rem` (except first-child case above).
- **Section transitions**: 2.5–3rem between semantic sections (intro → nav, nav → feed).
- **Figures, images, tables, pre blocks**: `margin: 1.75rem 0`.
- **`<hr>`**: 2.5rem vertical margin, subtle border via `rgba(var(--dot), 0.18)`.

## The ripple canvas

`<canvas class="ripple-canvas">` is fixed-positioned at `z-index: 0`, pointer-events none. It uses `--dot` (RGB tuple) and `--dot-base-opacity` / `--ripple-peak-opacity` for the dot matrix and interaction highlights. Keep content containers at `z-index: 1` to layer above it.

## Special content treatments

- **Code fences**: `pre:has(code.language-xxx)::before` drops a small uppercase language badge in the top-right (pinned, doesn't scroll with horizontal overflow). Extending to a new language is one `::before` rule.
- **Syntax highlighting**: rendered server-side via MDEx (using the Lumis highlighter with the `:html_linked` formatter). The highlighter emits semantic CSS class names — `keyword`, `string`, `comment`, `function`, `type`, `number`, and similar — which are mapped to the warm `--syntax-*`, `--link`, and `--text-muted` tokens in `assets/css/site.css`. The mapping flips automatically with light/dark via the same CSS custom property mechanism as the rest of the palette. Five tiers: keywords/decorators (buttery yellow `--syntax-keyword`, semi-bold 600), strings (peach `--link`), numbers/literals (amber `--syntax-amber`), types/built-ins/function-names (salmon `--syntax-rose` italic), comments (`--text-muted` italic). Everything else inherits body color. Do not introduce cool-tone token colors; the warm-only palette is load-bearing.
- **Blockquote**: 2px left border in `var(--link)`, italic, slight opacity.
- **Tables**: thin row borders in `rgba(var(--dot), 0.1)`, header borders slightly heavier. Uppercase letter-spaced header labels.
- **Images**: 6px border-radius. `<figure>` wraps with centered 0.85rem figcaption below.
- **Inline code**: subtle background `rgba(var(--dot), 0.1)`, 4px radius.
- **Scrollbars**: `scrollbar-gutter: stable` on `<html>` so opening the photo lightbox (which locks body scroll) doesn't reflow the page. `scrollbar-color` and `scrollbar-width: thin` apply to both `<html>` and `.post-body pre code` so code-block scrollbars match the page profile.

## Feed item variants

Feed items share `.feed-item` (display block, hover background). Variants layer on top:
- **Default post**: date + title + excerpt.
- **`.feed-item--book`**: single-paragraph `.feed-item-book` with `<cite>` for the title.
- **`.feed-item--photo`**: image-first with optional caption.

When adding a new variant, reuse `.feed-item-date` and the hover background — only the body shape changes.
