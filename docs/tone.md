# Tone

The writing voice across this site is quiet, literary, and specific. First-person where a person is speaking; present or past tense as chronology dictates. Short sentences let each claim land. The reader should feel like they're reading an essay, not a brochure — even in the resume, even in the feed metadata.

## Principles

**Specifics over abstractions.** Name the project, the system, the number, the constraint. "Touched various parts of the ecosystem" is a placeholder for a real sentence. "Built the Python executor that powered Try Python and Flying Through Python" is the real sentence.

**Prose over chrome.** If a list of skills, dates, or roles can be a muted inline sentence, make it one. Reach for chips, badges, and pills only when the information genuinely resists prose — which, in practice, is almost never.

**Time arcs over bag-of-tasks.** When describing a multi-year role, give the responsibilities a shape: "Early on, I worked alongside the contractors... As the team grew, I took on interviewing and mentoring." Not: "My responsibilities included X, Y, Z, and W."

**Don't duplicate signals context already provides.** Dates on a resume convey recency — so don't also open with "Recently joined". The feed's "RECENT" heading establishes recency — so items don't need to repeat it. Let structure carry what structure can carry.

**Proportion matters.** Senior roles should not have less to say than junior roles. If the most specific, longest entry on your resume is from six years ago, the reader draws a conclusion — probably not the one you want. Match substance to importance.

**First-person, active voice.** "I work across the stack..." not "Work includes...". "I built the Python executor" not "The Python executor was built by me". "We" when genuinely referring to a team; "I" when describing your own contribution.

**Short sentences earn trust.** A two-comma sentence usually splits into two clearer sentences. A "while", "where", or "all while" stitching clauses together is often a place to put a period.

## Phrases to avoid

Resume and startup clichés that the site's voice shouldn't speak:
- "Wore many hats"
- "0-to-1" / "zero to one" / "greenfield"
- "Scaling from zero to N"
- "Moved the needle"
- "Passionate about..."
- "Cutting-edge", "innovative", "world-class"
- "Leveraged", "synergy", "thought leader"
- "Touched various parts of..."
- "World's biggest [X], and everyone in between" and similar marketing boilerplate
- "Results-driven", "detail-oriented", "team player"

If a phrase could appear on any résumé, it shouldn't appear on this one.

## Editorial conventions

- **Date ranges**: em dash with spaces, `2021 — 2025`.
- **Current role**: `2025 — Present`. Not "Current". Pick one and stick with it across the whole site.
- **Meta separators**: middot (`·`), not pipe (`|`) or slash (`/`). `April 17, 2026 · 6 min read`.
- **Prose asides**: em dash with spaces, not parentheses: `the craft — the tools, the trade-offs, and the quiet decisions`. Parentheses are fine, but em dashes are the default.
- **Oxford comma**: yes.
- **Capitalization**: sentence case for headings, proper case only for named things (Point of Sale, Solutions RnD, Try Python).

## Per-context notes

### Resume entries

Each job follows this shape:

1. **Company description** — one sentence on what the company does. Present tense if it still exists; past tense if acquired or shuttered ("Code School, eventually acquired by Pluralsight, was an interactive code learning platform").
2. **Role paragraphs** — first-person. Past tense if the role ended; present tense if current. Lead with scope and stage for current roles, with specifics and outcomes for past roles.

The meta line under the company is always `dates · role`. Tech stack is deliberately omitted — it's noise at this point, and the writing should convey technical substance through specifics ("AST parsing and sandboxed execution") rather than name-dropping a stack.

### Posts

Essayistic, measured, reflective. Even technical posts ("Three Ways to Retry") open with a concrete scene or observation, not a thesis statement. Willing to name trade-offs and the "what this costs you" — not just advocate a position.

Opening lines should invite, not declare. Compare:
- **Do**: "Retry logic is one of those small utilities every codebase eventually needs. The network flakes. A database is briefly unreachable."
- **Don't**: "This post explains three approaches to retry logic."

### Feed items

Metadata first (date), then body. Titles are sentence-case and don't need to be catchy — they need to be honest about what the piece is. Excerpts are a sentence or two, trailed off with an ellipsis if they're a real excerpt of a longer piece.

Book entries use `<cite>` for the title and `var(--strong)` via CSS. "Read" or "Listened to" establishes medium. Keep it short: one sentence.

### Nav and section labels

Uppercase, muted. Single word when possible: POSTS, PHOTOS, READING, RESUME, RECENT. No sentence case, no em dashes, no additional framing. The letter-spacing and the muted color tier (`--text-muted`) do the work of making these feel like labels rather than links.

## When a sentence feels wrong

Ask:
- Is there a cliché I could replace with a specific?
- Is there a "we" or passive voice I could turn into "I" + active verb?
- Am I repeating a signal the page structure already conveys?
- Is there a clause stitched on with "while" or "all while" that wants to be its own sentence?
- Does the sentence sound like anyone could have written it about any job? If yes, make it sound like you.
