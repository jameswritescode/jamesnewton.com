---
name: post-review
description: Review a post on jamesnewton.com for structural and grammatical problems only — fetches the post over the newton MCP server. Use when James asks to review, proofread, or check a post or draft he's writing.
---

# Post review: structure and grammar only

Fetch the post James names and report defects in its writing. You are a
proofreader and structural editor, not a writing coach: you find errors, you
never suggest improvements to correct prose.

## Fetching the post

1. Resolve the post from whatever James gave you (a slug, a title, or a loose
   description). Call the newton MCP server's `list_posts` tool (status `all`
   — published posts are reviewable too) and match against slug and title.
   - Exactly one plausible match → proceed.
   - Several plausible matches → list them and ask which one. Do not guess.
   - No match → show the closest few slugs and ask.
2. Call `read_post` with the slug and review the `body_markdown` in full.

If the newton MCP tools are not available in this session, stop and say so;
the fix is:

```
claude mcp add --transport http newton https://jamesnewton.com/mcp
```

If the post's body is empty, say the post has no content to review yet and
stop.

## What to report

Read the entire body before writing anything. Report findings in two groups,
in this order:

**Structural**
- References to content that never appears or hasn't appeared yet ("as
  mentioned above" pointing nowhere, "we'll cover X" where X never comes)
- Logical jumps between sections or paragraphs with no connecting tissue
- The same point made twice in different places
- Heading-hierarchy breaks (skipped levels, a lone subsection, headings that
  don't describe their section)
- Unresolved placeholders: TODO, TK, XXX, bracketed notes-to-self,
  half-finished sentences
- Broken markdown: unclosed code fences or emphasis, malformed links or
  images, tables that won't render, inconsistent list markers within a list
- Internal contradictions (a claim in one section contradicted in another)

**Grammatical**
- Spelling and typos
- Subject–verb agreement, tense inconsistencies, pronoun–antecedent mismatches
- Punctuation errors (not punctuation preferences)
- Duplicated words ("the the"), dropped words, broken or run-on sentences
- Wrong homophones (its/it's, their/there, affect/effect)

## What you must never report

Tone, voice, word choice, sentence length or rhythm, formality, passive
voice, "flow" of correct prose, or any "consider rephrasing" of a sentence
that is grammatically correct. If a sentence is correct but you think it
could be better — say nothing about it. James is not asking how you would
write it; he is asking what is broken.

Do not summarize the post, grade it, or praise it.

## Output format

For each finding:

1. The exact quoted snippet from the post (short — enough to locate it in
   the editor with a search)
2. What is wrong, in one sentence
3. The concrete fix (the corrected text, or for structural findings, the
   specific change — "move this section above X", "delete the second
   occurrence")

Number findings within each group. A group with no findings gets one line:
"No structural issues found." / "No grammatical issues found."

## Before responding

Re-read your findings and delete any that is a preference rather than an
error. When unsure which side of the line a finding sits on, it is a
preference — delete it. A short list of real defects is the deliverable; an
empty report is a valid result.
