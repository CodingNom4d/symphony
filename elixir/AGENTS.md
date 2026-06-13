# Symphony Elixir

## Purpose

This directory contains the Elixir agent orchestration service that polls Linear, creates per-issue workspaces, and runs Codex in app-server mode.

## Ownership

- Owns the Elixir implementation under `lib/`, tests under `test/`, runtime configuration, workflow prompt loading, workspace management, and orchestration behavior.
- Owns `WORKFLOW.md` as the local workflow/config contract consumed by `SymphonyElixir.Workflow` and `SymphonyElixir.Config`.
- Parent repository rules in `../AGENTS.md` also apply.

## Local Contracts

- Runtime config is loaded from `WORKFLOW.md` front matter via `SymphonyElixir.Workflow` and `SymphonyElixir.Config`.
- Keep the implementation aligned with [`../SPEC.md`](../SPEC.md) where practical.
  - The implementation may be a superset of the spec.
  - The implementation must not conflict with the spec.
  - If implementation changes meaningfully alter the intended behavior, update the spec in the same change where practical so the spec stays current.
- Prefer adding config access through `SymphonyElixir.Config` instead of ad-hoc env reads.
- Workspace safety is critical:
  - Never run Codex turn cwd in source repo.
  - Workspaces must stay under configured workspace root.
- Orchestrator behavior is stateful and concurrency-sensitive; preserve retry, reconciliation, and cleanup semantics.
- Follow `docs/logging.md` for logging conventions and required issue/session context fields.
- PR body must follow `../.github/pull_request_template.md` exactly.
- If behavior or config changes, update docs in the same PR:
  - `../README.md` for project concept and goals.
  - `README.md` for Elixir implementation and run instructions.
  - `WORKFLOW.md` for workflow/config contract changes.

## Work Guidance

- Elixir: `1.19.x` (OTP 28) via `mise`.
- Install deps: `mix setup`.
- Public functions (`def`) in `lib/` must have an adjacent `@spec`.
- `defp` specs are optional.
- `@impl` callback implementations are exempt from local `@spec` requirement.
- Keep changes narrowly scoped; avoid unrelated refactors.
- Follow existing module/style patterns in `lib/symphony_elixir/*`.
- Validate PR bodies locally when needed with `mix pr_body.check --file /path/to/pr_body.md`.

## Verification

Run targeted tests while iterating, then run full gates before handoff when implementation behavior changes.

`WORKFLOW.md` changes alter the unattended agent prompt and must run the main quality gate unless a narrower prompt-loader/runtime validation is added and documented in the same change. For unattended-agent contract wording, keep `SymphonyElixir.WorkflowContract` and `test/symphony_elixir/workflow_contract_test.exs` current and run that focused test.

Main quality gate:

```bash
make all
```

Required-rule validation:

```bash
mix specs.check
```

## Child DOX Index

No child `AGENTS.md` files are currently indexed under this directory.
