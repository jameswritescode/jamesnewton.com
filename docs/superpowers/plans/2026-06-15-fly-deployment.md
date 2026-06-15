# Fly.io Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Produce the container + Fly artifacts (Dockerfile, .dockerignore, release entrypoints, fly.toml) so the app deploys to Fly.io as a single LAX machine with a persistent media volume, backed by the existing Managed Postgres.

**Architecture:** Build a `mix release` image via a multi-stage Dockerfile. The build installs Elixir deps **and the pnpm JS deps** (CodeMirror et al.) so `mix assets.deploy` can bundle, then assembles the release; a slim runtime stage runs `/app/bin/server`. `fly.toml` pins the app to LAX, mounts the media volume, and runs migrations via `release_command`. No application code changes — `runtime.exs` and `Newton.Release` are already deploy-ready.

**Tech Stack:** Elixir/Phoenix release, Docker (multi-stage), Fly.io, pnpm (assets), esbuild + tailwind (Hex standalone wrappers).

---

## Context for the implementer

Read the spec first: `docs/superpowers/specs/2026-06-15-fly-deployment-design.md`.

**This is infrastructure work, not TDD.** There are no unit tests; "verification"
means **`docker build` succeeds locally** and `mix precommit` stays green. Run
each build step and confirm its output before committing.

**Critical build fact — the JS bundle needs pnpm deps.** `assets/js/admin.js`
imports CodeMirror packages (`@codemirror/*`, `@lezer/highlight`, `codemirror`)
that live in `assets/node_modules` (installed by **pnpm**, lockfile
`assets/pnpm-lock.yaml`). esbuild also resolves Phoenix JS from `deps/` and
colocated hooks from the Mix build path (via `NODE_PATH` in `config/config.exs`).
So the image build order must be: `mix deps.get` → `mix compile` (generates
colocated hooks) → **`pnpm install` in `assets/`** → `mix assets.deploy`. The
stock `phx.gen.release` Dockerfile omits the pnpm step; adding Node + pnpm +
`pnpm install` is the main adaptation in this plan.

**Versions (pin the builder image to these):**
- Elixir `~> 1.15` (dev uses 1.20.0), **Erlang/OTP 29** (erts 17.0.1).
- esbuild `0.25.4`, tailwind `4.1.12` (from `config/config.exs`; standalone
  binaries, installed by `assets.setup` — no Node needed to *run* them).
- pnpm: the assets use pnpm (per project rules); install via `corepack`.

**Already deploy-ready (do not modify):**
- `config/runtime.exs` — reads `DATABASE_URL`, `SECRET_KEY_BASE`, `PHX_HOST`,
  `PORT`, `PHX_SERVER`; sets `media_root` to `/data/images` in prod; enables
  IPv6 DB socket options.
- `lib/newton/release.ex` — `migrate/0`, `create_admin/2`.
- `mix.exs` — `assets.deploy` alias (`tailwind newton --minify`,
  `esbuild newton --minify`, `phx.digest`).

**Rules:** pnpm (never npm) for assets. Don't commit broken builds — verify each
`docker build` before committing. `mix precommit` at the end.

## File structure

| File | Responsibility | Action |
| --- | --- | --- |
| `Dockerfile` | Multi-stage release image (incl. pnpm asset install) | Create |
| `.dockerignore` | Lean, correct build context | Create |
| `rel/overlays/bin/server` | Release web entrypoint (`PHX_SERVER=true`) | Create |
| `rel/overlays/bin/migrate` | Migration runner (`Newton.Release.migrate()`) | Create |
| `fly.toml` | App/region/volume/release-command config | Create |

---

## Task 1: Generate the base release artifacts

**Files:**
- Create: `Dockerfile`, `.dockerignore`, `rel/overlays/bin/server`, `rel/overlays/bin/migrate`

Use Phoenix's generator for a correct, version-matched starting point, then we
adapt the Dockerfile in Task 2.

- [ ] **Step 1: Run the release generator**

Run: `mix phx.gen.release --docker`
Expected: creates `Dockerfile`, `.dockerignore`, `rel/overlays/bin/server`,
`rel/overlays/bin/migrate`, and prints next-step notes. Answer no to overwriting
anything unexpected (there should be no conflicts — none of these exist yet).

- [ ] **Step 2: Confirm the generated entrypoints**

Run: `cat rel/overlays/bin/server rel/overlays/bin/migrate`
Expected: `server` sets `PHX_SERVER=true` and execs `./newton start`; `migrate`
runs `./newton eval Newton.Release.migrate()`. Confirm the app name in the paths
is `newton` (matches `mix.exs` `app: :newton`). These are correct as generated —
no edits.

- [ ] **Step 3: Confirm the builder image versions**

Run: `grep -E "ARG ELIXIR_VERSION|ARG OTP_VERSION|ARG DEBIAN_VERSION|^FROM" Dockerfile`
Expected: the generator pins `ELIXIR_VERSION`/`ERLANG_VERSION`/`DEBIAN_VERSION`
ARGs. Verify `ERLANG_VERSION` is a 29.x (matches local OTP 29). If the generator
picked an older Elixir/OTP than the project supports, bump `ELIXIR_VERSION` to a
1.18+ release and `ERLANG_VERSION` to `29.x` so the image matches the dev
toolchain. (Elixir requirement is `~> 1.15`, so 1.18.x is fine.)

- [ ] **Step 4: Commit the generated baseline**

```bash
git add Dockerfile .dockerignore rel/overlays/bin/server rel/overlays/bin/migrate
git commit -m "Generate Phoenix release Docker artifacts"
```

---

## Task 2: Adapt the Dockerfile to install pnpm JS deps

**Files:**
- Modify: `Dockerfile`

The stock Dockerfile builds assets with `mix assets.deploy` but never installs
the npm packages esbuild bundles. Add Node + pnpm and a `pnpm install` step
before `assets.deploy`.

- [ ] **Step 1: Inspect the generated build stage**

Run: `sed -n '1,60p' Dockerfile`
Expected: a builder stage on `hexpm/elixir:...-debian-...` that runs
`apt-get install ... build-essential git`, `mix deps.get --only prod`,
`mix deps.compile`, copies `assets`, then `mix assets.deploy` and `mix release`.
Note the exact line that copies `assets` and the line that runs
`mix assets.deploy` — the pnpm install goes between them.

- [ ] **Step 2: Add Node + pnpm to the builder's apt install**

In the builder stage's `apt-get install` line, add `curl ca-certificates`, then
add a step to install Node 22 + enable corepack/pnpm. After the existing
`RUN apt-get update -y && apt-get install -y ... build-essential git ...` line,
add:

```dockerfile
# Node + pnpm for the JS bundle (esbuild bundles CodeMirror from assets/node_modules)
RUN apt-get install -y curl ca-certificates \
    && curl -fsSL https://deb.nodesource.com/setup_22.x | bash - \
    && apt-get install -y nodejs \
    && corepack enable && corepack prepare pnpm@latest --activate
```

(If the base image's apt list is already updated earlier in the file, this `RUN`
can rely on that; otherwise prefix with `apt-get update -y &&`.)

- [ ] **Step 3: Install the JS deps before building assets**

The generated Dockerfile has lines like:

```dockerfile
COPY assets assets
# ... then later:
RUN mix assets.deploy
```

Insert a pnpm install between the `COPY assets assets` (and the `deps`/compile
steps it needs) and `mix assets.deploy`. Ensure this order holds:

```dockerfile
# deps + compile must run first (compile generates the colocated JS hooks that
# esbuild resolves via NODE_PATH = build_path)
RUN mix deps.get --only $MIX_ENV
RUN mix deps.compile
COPY assets assets
RUN pnpm install --prefix assets --frozen-lockfile
COPY priv priv
RUN mix assets.deploy
```

If the generated file already has `COPY assets assets` and `mix assets.deploy`,
just add the single line `RUN pnpm install --prefix assets --frozen-lockfile`
immediately before `RUN mix assets.deploy`, and confirm `mix deps.compile` (or
`mix compile`) runs before `assets.deploy` so colocated hooks exist. (esbuild
resolves `@codemirror/*` from `assets/node_modules`, Phoenix JS from `deps`, and
`phoenix-colocated/newton` from the build path.)

- [ ] **Step 4: Build the image locally to verify**

Run: `docker build -t newton:deploy-test .`
Expected: PASS — completes through `pnpm install`, `mix assets.deploy` (esbuild
bundles app.js + admin.js with no "Could not resolve" errors), `mix release`, and
the runtime stage. If esbuild reports an unresolved import, the pnpm install or
the deps/compile ordering is wrong — fix and rebuild before continuing.

- [ ] **Step 5: Sanity-check the built image boots**

Run:
```bash
docker run --rm -e SECRET_KEY_BASE=$(mix phx.gen.secret) -e DATABASE_URL=ecto://u:p@localhost/db \
  -e PHX_SERVER=true newton:deploy-test /app/bin/newton eval 'IO.puts("boot ok")'
```
Expected: prints `boot ok` (the release assembles and runs; it won't connect to
the fake DB, but `eval` doesn't need it). If it errors on a missing runtime env
var, that's fine to note — the real values come from Fly secrets.

- [ ] **Step 6: Commit**

```bash
git add Dockerfile
git commit -m "Install pnpm JS deps in the release image build"
```

---

## Task 3: Write fly.toml

**Files:**
- Create: `fly.toml`

- [ ] **Step 1: Create `fly.toml`**

```toml
app = "jamesnewton-com"
primary_region = "lax"

[build]

[env]
  PHX_HOST = "jamesnewton-com.fly.dev"
  PORT = "8080"

[http_service]
  internal_port = 8080
  force_https = true
  auto_stop_machines = "stop"
  auto_start_machines = true
  min_machines_running = 1

[[mounts]]
  source = "media"
  destination = "/data/images"
  auto_extend_size_threshold = 80
  auto_extend_size_increment = "1GB"
  auto_extend_size_limit = "10GB"

[deploy]
  release_command = "/app/bin/migrate"

[[vm]]
  size = "shared-cpu-1x"
  memory = "1gb"
```

- [ ] **Step 2: Validate the config**

Run: `fly config validate` (requires flyctl; if not authed, this still parses the
file and reports schema errors). If flyctl is unavailable in this environment,
visually confirm the TOML matches the spec: app `jamesnewton-com`, region `lax`,
internal port `8080` matching `[env] PORT`, mount `/data/images` matching
`media_root`, `release_command` = `/app/bin/migrate`.

- [ ] **Step 3: Confirm runtime.exs aligns with fly.toml**

Run: `grep -nE "PORT|PHX_HOST|media_root|PHX_SERVER" config/runtime.exs config/prod.exs`
Expected: `runtime.exs` reads `PORT` (defaulting 4000 — overridden to 8080 by
`[env]`), uses `PHX_HOST` for the endpoint URL, and `prod.exs`/`runtime.exs` set
`media_root` to `/data/images`. No code change — just confirm they match the
fly.toml values.

- [ ] **Step 4: Commit**

```bash
git add fly.toml
git commit -m "Add fly.toml for the LAX single-machine deploy"
```

---

## Task 4: Tighten .dockerignore and final verification

**Files:**
- Modify: `.dockerignore`

- [ ] **Step 1: Ensure the build context excludes local-only + heavy paths**

Open `.dockerignore` and confirm it ignores (add any missing):

```
_build/
deps/
assets/node_modules/
priv/static/assets/
.git/
.elixir_ls/
docs/
test/
.dockerignore
Dockerfile
fly.toml
assets/screenshot.mjs
```

Rationale: `deps`/`_build`/`node_modules` are rebuilt in the image (stale host
copies must not leak in); `priv/static/assets` is regenerated by
`assets.deploy`; `assets/screenshot.mjs` is a local-only dev tool. Keep
`priv/` itself (needed for static files, gettext, repo migrations) — only the
generated `priv/static/assets/` build output is excluded.

- [ ] **Step 2: Rebuild to confirm the leaner context still builds**

Run: `docker build -t newton:deploy-test .`
Expected: PASS — a clean build from the trimmed context (this also proves the
build doesn't secretly depend on host `_build`/`node_modules`).

- [ ] **Step 3: Run the app test suite (no code changed, but confirm green)**

Run: `mix precommit`
Expected: PASS — compile/format/credo/tests/dialyzer all green (this plan adds no
app code, so it should be unaffected; this catches any accidental edit).

- [ ] **Step 4: Commit**

```bash
git add .dockerignore
git commit -m "Trim the Docker build context"
```

---

## Task 5: Deploy runbook (operator-run; not automated)

These steps require authenticated `flyctl` and touch the user's account/billing,
so the **user** runs them (inline with `! fly …` so output returns here, or
independently). They are documented in the spec; reproduced here as the
execution checklist. Run from the `phoenix-migration` checkout.

- [ ] **Step 1: Create the app** — `fly apps create jamesnewton-com`
- [ ] **Step 2: Create the volume** — `fly volumes create media --region lax --size 1 -a jamesnewton-com`
- [ ] **Step 3: Dedicated db + user on the existing MPG cluster**
  - `fly mpg databases create` → create `newton`
  - `fly mpg users create` → app user scoped to `newton`
  - Attach `jamesnewton-com` using that user/db (Connect tab or flyctl) so
    `DATABASE_URL` is set to the least-priv app credentials (not `fly-user`).
- [ ] **Step 4: Set the secret** — `fly secrets set SECRET_KEY_BASE="$(mix phx.gen.secret)" -a jamesnewton-com`
- [ ] **Step 5: Deploy** — `fly deploy` (builds image, runs `/app/bin/migrate` as
  the release command, boots `/app/bin/server`)
- [ ] **Step 6: Create the admin** —
  `fly ssh console -a jamesnewton-com -C "/app/bin/newton eval 'Newton.Release.create_admin(\"hello@jamesnewton.com\", \"<strong-password>\")'"`
- [ ] **Step 7: Smoke test** — visit `https://jamesnewton-com.fly.dev`, log in at
  `/login`, upload a photo (confirms the volume), confirm public pages render.

---

## Self-review notes

- **Spec coverage:** Dockerfile + entrypoints (Tasks 1–2); the pnpm/JS-deps build
  requirement, which the spec flagged as "verify the image builds without Node"
  — resolved decisively here: Node+pnpm **are** required to install CodeMirror,
  though esbuild/tailwind themselves run as standalone binaries (Task 2);
  fly.toml incl. volume auto-extend + release_command + vm size (Task 3);
  .dockerignore (Task 4); the full CLI runbook incl. dedicated db+user (Task 5).
- **Deviation from spec:** the spec's open question "does the image build assets
  without Node?" is answered **no** — the build needs Node + pnpm for the npm
  packages. This is handled in Task 2; the app still needs no Node at *runtime*.
- **No placeholders:** every file's content is given; `<strong-password>` in the
  runbook is an intentional operator value, and the Dockerfile edits reference the
  generator's output (inspected in Task 2 Step 1 before editing).
- **Verification is operational:** `docker build` after Tasks 2 and 4, `fly config
  validate` for fly.toml, `mix precommit` at the end. No unit tests (infra).
- **Out of scope (per spec):** custom domain, object storage, CI/CD, scaling.
