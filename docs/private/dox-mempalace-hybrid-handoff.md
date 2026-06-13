# Private Branch Handoff: DOX/MemPalace Hybrid

This note is for the private `dox-mempalace-hybrid` branch only. It is intentionally not an upstream-facing document and can be dropped before upstreaming if desired.

## Baseline

- Branch visibility: intentionally private for now.
- Baseline tag: `private-dox-mempalace-validated`
- Baseline commit: `85ed73a9e74ddc6235c837686f82dcc8ed47fc33`

## Branch Contents

- DOX/MemPalace workflow contracts for unattended Symphony agents.
- Repo-local canonical DOX skill at `.codex/skills/dox/SKILL.md`.
- `SymphonyElixir.WorkflowContract` validator and focused tests for critical prompt contracts.

## Validation

Run validation from `elixir/` with Docker:

```bash
docker run --rm -v "${PWD}:/work" -w /work elixir:1.19.5-otp-28 bash -lc "mix deps.get && make all"
```

If LiveView tests fail with `LazyHTML.NIF.from_document/1` unavailable, compile `lazy_html` inside the same Docker/mounted environment, then rerun `make all`:

```bash
docker run --rm -v "${PWD}:/work" -w /work elixir:1.19.5-otp-28 bash -lc "mix deps.get && MIX_ENV=test mix deps.compile lazy_html --force && make all"
```

Current validation evidence:

- Docker `make all` passed.
- ExUnit: 245 tests, 0 failures, 2 skipped.
- Coverage: 100%.
- Dialyzer passed.
- Missing-Linear app-server dry run passed in Docker with `codex-cli 0.139.0`.
  - The dry-run agent kept the repository read-only.
  - `linear_graphql` was injected, but unauthenticated with no `LINEAR_API_KEY`.
  - The Linear request failed with `:missing_linear_api_token`.
  - Final response included `blocked: missing Linear tool/auth`.

The app-server dry run should copy stable Codex config/auth files into container-local `/root/.codex` instead of bind-mounting the live host Codex home there; a direct Windows bind mount can fail SQLite state initialization.

## Upstreaming Status

Upstreaming remains blocked by missing `openai/symphony` permissions. The public fork feature branch is absent.
