# Known issues (upstream, monitored)

Issues in dependencies we can't fix in our own code, with why they're accepted
and what would resolve them.

## phoenix_seo emits JSON-LD without HTML-escaping (`</script>` breakout) — RESOLVED in our code

**Status: closed on our side (2026-07-30).** The upstream bug is still present in
phoenix_seo 0.3.1, but it is no longer reachable here.

**The bug:** `deps/phoenix_seo/lib/seo/json_ld.ex` renders the JSON-LD block with
`Phoenix.HTML.raw(@json_library.encode!(@item))`. Jason's default escaping leaves
`<` and `/` untouched, so a value containing the literal bytes `</script>` closes
the element early — an HTML parser terminates a script element on the first
`</script` sequence regardless of the element's `type` — and whatever follows is
parsed as live markup. On `/posts/:slug` the post `title` and `excerpt` feed that
record, so an author-written title could inject markup into every visitor's
`<head>`.

**How we closed it:** `@json_library` is *our* value, not the dependency's. It is
passed at `use SEO, json_library: ...` in `lib/newton_web/seo.ex` and threaded
through to that call site. It now points at `NewtonWeb.SEO.HtmlSafeJson`, a thin
Jason wrapper whose `encode!/1` supplies `escape: :html_safe`. That escapes `<`
to `\u003C` and `/` to `\/`, which keeps the output valid JSON-LD (consumers
decode the escapes transparently) while making the breakout impossible. No
dependency patch, and no lossy sanitizing of author text.

Regression coverage: `test/newton_web/controllers/seo_meta_test.exs` requests a
published post whose title and excerpt both contain `</script>` payloads and
asserts the rendered block contains no live markup and still decodes to the
original strings.

*(Earlier revisions of this file claimed the fix required editing `deps/` or
sanitizing input. That was wrong — the `:json_library` seam was always ours.)*

**Upstream:** still worth a one-line PR to `github.com/dbernheisel/phoenix_seo`
so other users get the safe default.

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
