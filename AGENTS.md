# Symphony

## Purpose

This repository defines Symphony, an orchestration service for running Codex agents against tracked project work in isolated per-issue workspaces.

## Ownership

- Root files own project-wide intent, specifications, operator docs, and repository-level workflow.
- `elixir/AGENTS.md` owns the Elixir orchestration service and its local implementation rules.
- `.codex/skills/dox/SKILL.md` owns the repo-local canonical DOX skill. Machine-local installed copies may mirror it for deployment, but the versioned repo copy is the source for Symphony changes.

## Local Contracts

- Read this file before editing anywhere in the repository.
- Use `.codex/skills/dox/SKILL.md` as the canonical DOX workflow definition when changing Symphony's DOX behavior or local skill content.
- For any target path, also read every child `AGENTS.md` from the repository root to that path.
- The nearest applicable `AGENTS.md` controls local details. Parent docs still apply for broader rules.
- Keep implementation behavior aligned with `SPEC.md` where practical. If a meaningful behavior change conflicts with or extends the spec, update the spec in the same change where practical.
- Use MemPalace or semantic memory only for recall and discovery. Scope recall to the current repository, current task or issue, and explicitly relevant local Codex skills or rules unless the user asks for broader memory. Binding instructions must come from files in the current workspace.
- Do not publish recalled content into Linear, PRs, issues, or durable docs unless it has been re-verified against current workspace files or the user explicitly asks to use that recalled source. Keep provenance for material memory-derived facts without copying private recalled content.

## Work Guidance

- Keep changes narrowly scoped to the ticket or user request.
- Preserve unattended orchestration behavior: agents should work in per-issue workspaces and avoid touching unrelated paths.
- Update durable docs when behavior, workflow, configuration contracts, ownership, or repository structure changes.
- Treat missing, stale, or contradictory child `AGENTS.md` index entries as documentation defects; fix them when in scope or report why they were deferred.
- Do not treat generated workspaces, logs, or temporary run artifacts as source unless the task explicitly targets them.

## Verification

- Prefer targeted checks while iterating.
- Run the closest applicable validation for the changed surface before handoff.
- For Elixir implementation changes, follow `elixir/AGENTS.md`.
- For docs-only or prompt-only changes, review the rendered text and relevant diffs.

## Child DOX Index

- `elixir/AGENTS.md`: Elixir agent orchestration service, including runtime config, workflow prompt handling, workspace safety, validation gates, and PR rules.
