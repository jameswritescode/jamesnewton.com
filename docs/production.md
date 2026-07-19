# Production launch checklist: pointing jamesnewton.com at Fly

Everything that must happen when the real domain cuts over to the Fly app
(currently serving as staging at `jamesnewton-com.fly.dev`). Roughly in order.

## 1. DNS and certificates

- `fly certs add jamesnewton.com` and add the A/AAAA records it prints at the
  DNS host. Decide on `www`: either add `fly certs add www.jamesnewton.com`
  plus a redirect, or leave `www` unconfigured. (Sitemaps, canonicals, and the
  standard.site publication all use the apex — keep apex primary.)
- **Do not touch the `_atproto` TXT record** — it verifies the Bluesky handle
  `jamesnewton.com` and is independent of the A records.

## 2. Flip `PHX_HOST`

In `fly.toml` `[env]`: `PHX_HOST = "jamesnewton.com"`, then deploy.
Everything host-derived follows automatically — canonical URLs, og/twitter
meta, JSON-LD, `sitemap.xml`/`robots.txt`, IndexNow-submitted URLs, and
WebAuthn `rp_id`/`origin` (see next item). The old `fly.dev` host keeps
serving, but every page's canonical now points at the real domain, so search
consolidates correctly.

## 3. Passkeys break — on purpose, by the spec

WebAuthn credentials are bound to `rp_id`, which is derived from `PHX_HOST`.
Passkeys registered against `jamesnewton-com.fly.dev` will not work on
`jamesnewton.com`:

1. Log in with the password instead.
2. Settings → delete the stranded fly.dev passkeys.
3. Register fresh passkeys on the new domain.

## 4. Enable IndexNow

- `config/prod.exs`: `config :newton, Newton.IndexNow, enabled: true`
  (the comment there points here). Deploy.
- The key file (`/d1258f1d59aea5c8f3e604eb494cc477.txt`) is already in
  `static_paths` and becomes reachable on the new host automatically.
- Details: `docs/indexnow.md`.

## 5. Enable standard.site

- `fly secrets set BSKY_APP_PASSWORD=<app password>` (create one in Bluesky
  settings; never the account password).
- Run `mix standard.put_publication` (one-time; prints the publication AT-URI)
  and set it in config.
- `config/prod.exs`: `config :newton, Newton.Standard, enabled: true`. Deploy.
- Create records for the already-published posts (touch-save each in the
  editor, or `Newton.Standard.put_document/1` from IEx).
- Verify: `curl https://jamesnewton.com/.well-known/site.standard.publication`
  returns the AT-URI; a post page's head carries the
  `site.standard.document` link tag. AppView verification proceeds from there.

## 6. Search engines

- **Google Search Console:** add the `jamesnewton.com` property and submit
  `https://jamesnewton.com/sitemap.xml` once. Google polls it afterwards;
  no programmatic resubmission exists or is needed.
- Bing/Yandex/etc. are covered by IndexNow once enabled.

## 7. Post-cutover verification pass

- `curl https://jamesnewton.com/robots.txt` — `Sitemap:` line carries the new
  host (it's dynamic; this is the check that it's true).
- `curl https://jamesnewton.com/sitemap.xml` — locs on the new host.
- View-source a post page: `og:url`, canonical, and JSON-LD on the new host.
- fly-metrics.net → Explore → confirm `phoenix_*`/`newton_*` series still
  flowing (and do the one-time custom-metrics sanity check if never done).
- Admin dashboard: `hourly_views` keeps counting across the cutover — paths
  are host-agnostic, so analytics history carries straight through.
- Unfurl a post in Discord/Slack: new-domain URLs get fresh embed caches by
  definition (old fly.dev embed caches are irrelevant).

## Notes

- The fly.dev hostname cannot be unserved on Fly, but canonicals point at the
  apex after step 2, which is the accepted pattern.
- Analytics needs nothing: buckets are keyed by path, not host.
- If anything here changes (new integrations gated on launch), add the flip
  to this list when the gate is added — this file is the single launch
  runbook.
