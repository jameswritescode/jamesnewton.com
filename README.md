# jamesnewton.com

[![CI](https://github.com/jameswritescode/jamesnewton.com/actions/workflows/ci.yml/badge.svg)](https://github.com/jameswritescode/jamesnewton.com/actions/workflows/ci.yml)

Personal site and blog, built with Phoenix LiveView. Posts are written in
markdown in a custom CodeMirror editor with autosave, inline image uploads,
and optimistic-locking conflict protection; the public site adds photo
galleries, a reading log, server-rendered social cards, and privacy-preserving
first-party analytics.

## Stack

- Elixir / Phoenix 1.8 / LiveView, Postgres via Ecto
- Tailwind CSS v4 + esbuild; JS deps managed with pnpm in `assets/`
- Deployed on Fly.io (`fly deploy`); metrics via PromEx → Grafana

Tool versions are pinned in `mise.toml` (Elixir, Erlang/OTP, pnpm).

## Development

```bash
mix setup          # deps, database, assets
mix phx.server     # http://localhost:4000
```

Sign-in supports password and passkeys; security-sensitive settings require a
fresh re-auth (sudo mode).

## Checks

`mix precommit` is the local gate: compile with warnings as errors, unused-dep
check, formatter, Credo (strict), ExUnit, vitest (`assets/`), and Dialyzer.
CI (`.github/workflows/ci.yml`) runs the same checks in assert-only form
against Postgres 14.

## Docs

- `docs/production.md` — deploy/launch runbook
- `docs/known-issues.md` — accepted upstream issues and why
- `docs/analytics.md`, `docs/indexnow.md`, `docs/design.md` — subsystem notes
- `docs/superpowers/specs/` — design docs for larger features
