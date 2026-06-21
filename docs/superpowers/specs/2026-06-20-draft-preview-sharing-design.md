# Draft Preview Sharing — Design Spec

**Date:** 2026-06-20
**Status:** Approved (pending written review)
**Branch context:** `phoenix-migration`

## Overview

Let the author share an **unpublished draft** with someone who isn't signed in,
via an unguessable link on the normal post URL:

```
https://jamesnewton.com/posts/<slug>?p=<token>
```

A per-post token is toggled on/off from the editor's settings drawer. Sharing is
**draft-only**: publishing the post clears the token and hides the control. This
is a deliberate, narrow exception to the "no drafts on the public side" rule from
the security audit — the token unlocks exactly one post and nothing else.

## Decisions (locked)

- **URL:** query param `?p=<token>` on `/posts/:slug` — no new route.
- **Scope:** one token per post (`preview_token`), simple on/off.
- **Control:** a toggle in the editor's publish/settings drawer.
- **Draft-only:** publishing removes the token and hides the control.
- **New posts:** the toggle is disabled until the post is first saved (has an id).
- **Out of scope:** multiple/named links, expiry, proofing comments.

## Section 1 — Data & context (`Newton.Blog`)

- **Migration:** add `preview_token :string` (nullable) to `posts`. No index
  needed (lookups are by `slug`).
- **Schema (`Newton.Blog.Post`):** add `field :preview_token, :string`. It is
  **not** added to the `cast/2` list — it can never be mass-assigned from the
  editor form.
- **Clear on publish (changeset):** in the changeset, once the post is published
  (`published_at` is non-nil), force `preview_token` to `nil`. This guarantees a
  published post never carries a token, regardless of which path published it.
- **Context functions:**
  - `enable_preview(%Post{} = post)` — if `preview_token` is nil, set it to a
    fresh `32 |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)`
    via a programmatic changeset (`put_change`), then `Repo.update`. Intended for
    drafts only (the UI gates it; see Section 3).
  - `disable_preview(%Post{} = post)` — `put_change(:preview_token, nil)` →
    `Repo.update`.
  - `get_post_by_preview_token(slug, token)` — load the post by slug; return it
    only if `preview_token` is non-nil and **`Plug.Crypto.secure_compare(token,
    preview_token)`** is true; otherwise `nil`. Constant-time comparison.

## Section 2 — Public render (`PostController.show`)

`show/2` reads the optional `p` param and passes it to `fetch_post`:

- **Logged-in admin** → any post by slug (unchanged).
- **Public + a `p` token matching the post's `preview_token`** → that post,
  regardless of publish status. Sets a preview flag.
- **Public, no/invalid token** → published-only (`get_published_post!`, 404 for a
  draft) — unchanged.

Sketch:

```elixir
def show(conn, %{"slug" => slug} = params) do
  case fetch_post(conn.assigns.current_scope, slug, params["p"]) do
    {:preview, post} ->
      conn
      |> assign(:page_robots, "noindex")
      |> render(:show, page_title: post.title, post: post, preview: true)

    post ->
      render(conn, :show, page_title: post.title, post: post, preview: false)
  end
end

defp fetch_post(%{user: %{}}, slug, _token), do: Blog.get_post_by_slug!(slug)

defp fetch_post(_scope, slug, token) when is_binary(token) do
  case Blog.get_post_by_preview_token(slug, token) do
    %Post{} = post -> {:preview, post}
    nil -> Blog.get_published_post!(slug)
  end
end

defp fetch_post(_scope, slug, _), do: Blog.get_published_post!(slug)
```

The preview render only unlocks the one post the token belongs to; there is no
query that could enumerate other drafts.

## Section 3 — Editor control (publish/settings drawer)

In the editor's publish drawer, add a **"Preview link"** section, shown only when
the post is a **draft** (`published_at == nil`):

- **New, unsaved post (no id):** show the control **disabled** with a hint
  ("Save the draft to share a preview"). No token can exist without a row.
- **Saved draft, sharing off:** a toggle/button "Enable preview link". Clicking
  fires `enable_preview`, persists the token immediately (like "Publish now"
  does), and re-renders to show the link.
- **Saved draft, sharing on:** show the full shareable URL (read-only) with a
  **Copy** button, and a control to **turn it off** (`disable_preview`, clears the
  token → existing links 404).
- **Published post:** the whole "Preview link" section is **hidden**; publishing
  has already cleared the token (Section 1).

The displayed URL uses an absolute verified route:
`url(~p"/posts/#{post.slug}?#{[p: post.preview_token]}")`.

The token toggle persists independently of the body autosave, mirroring the
existing immediate-persist publish controls.

**Copy button:** a small colocated JS hook (`navigator.clipboard.writeText`) on a
button carrying the URL (e.g. a `data-clipboard-text` attribute). Pure helper for
the value is unit-testable; the clipboard call itself is exercised by e2e/manual.
Works under the strict CSP (it's in the `app.js` bundle, `script-src 'self'`).

## Section 4 — Preview affordances on the public page

When `preview: true`:

- Render a **"Draft preview"** banner at the top of the post so the viewer knows
  it's an unpublished draft, not the live page.
- The root layout renders `<meta name="robots" content={assigns[:page_robots]}>`
  **only when `@page_robots` is assigned** (set to `"noindex"` in the preview
  branch). Published posts and all other pages get no robots meta (default
  indexable).

## Error handling / edge cases

- **Wrong/blank/old token:** `secure_compare` fails (or token is nil) → falls
  back to published-only → 404 for a draft. Turning sharing off clears the token,
  so previously shared links 404 immediately.
- **Slug changes after sharing:** the link is `/posts/<slug>?p=<token>`; if the
  slug changes, the old link 404s. Acceptable — reshare the new URL.
- **Published while a link is out:** publish clears the token (Section 1); the old
  preview link 404s, but the post is now public at its normal URL anyway.
- **Token in the URL can leak via `Referer`** if the draft links out to another
  site. Low risk for a proofing link. Optional hardening (deferred unless wanted):
  a stricter `Referrer-Policy` or `rel="noreferrer"` on outbound links.

## Testing approach

- **Context (`Newton.Blog`):** `enable_preview` mints a token; `disable_preview`
  clears it; `get_post_by_preview_token` returns the post for a correct token and
  `nil` for a wrong one; publishing (a changeset with `published_at`) clears an
  existing token.
- **Controller (`PostController`):** a draft with a valid `?p=` renders (200, body
  present); a draft with a wrong/missing `?p=` is 404; a published post still
  renders without a token; a logged-in admin is unchanged. Assert the preview
  response carries `noindex` and the published one does not.
- **Editor LiveView:** for a saved draft, enabling shows the URL and persists the
  token; disabling clears it; the control is **hidden for a published post** and
  **disabled for a brand-new unsaved post**.
- **vitest:** the copy hook's value helper (reads the target text).

## Unit breakdown

- `priv/repo/migrations/*_add_preview_token_to_posts.exs` — new column.
- `lib/newton/blog/post.ex` — field, clear-on-publish, (token stays out of cast).
- `lib/newton/blog.ex` — `enable_preview/1`, `disable_preview/1`,
  `get_post_by_preview_token/2`.
- `lib/newton_web/controllers/post_controller.ex` — `?p` handling + preview flag.
- `lib/newton_web/controllers/post_html/show.html.heex` — draft-preview banner.
- `lib/newton_web/components/layouts/root.html.heex` — conditional robots meta.
- `lib/newton_web/live/admin/post_live/editor.ex` — drawer control + events.
- `assets/js/hooks/*.js` — clipboard copy hook.

## Out of scope (future follow-ups)

- Multiple/named share links and per-link revocation.
- Link expiry / TTL.
- Friend-facing proofing comments or inline feedback.
- Referrer hardening (unless requested).
