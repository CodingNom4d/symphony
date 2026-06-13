# DOX and MemPalace Hybrid Design

## Goal

Implement a local Codex and Symphony workflow where deterministic `AGENTS.md` files define binding project instructions, while MemPalace provides local semantic recall and discovery.

## Scope

This design covers:

- a versioned repo-local Codex DOX skill at `.codex/skills/dox/SKILL.md` for reading and applying `AGENTS.md` instruction chains
- Symphony repository `AGENTS.md` contracts and workflow prompt guidance
- MemPalace usage as a local recall index for related docs, decisions, and prior sessions

This design does not make semantic search authoritative for instructions. Binding rules must come from files in the active workspace.

## Architecture

The workflow has two layers.

The DOX layer is deterministic. Before planning, review, workpad updates, repo analysis, or editing, the agent identifies target paths, reads the repository root `AGENTS.md`, walks from the root to each target path, and reads every applicable child `AGENTS.md`. The nearest applicable `AGENTS.md` owns local details, while parent docs continue to apply for broader rules. After meaningful edits, the agent performs a closeout pass and updates the nearest owning docs when behavior, structure, workflow, contracts, or ownership changed.

The MemPalace layer is semantic. It may be used to mine Symphony, local Codex skills, local instructions, and session history. It helps find relevant decisions and related documentation, but it does not override or replace the checked-out `AGENTS.md` chain.

## Local Codex Behavior

Add a repo-local Codex skill named `dox` at `.codex/skills/dox/SKILL.md`. It should trigger for planning, read-only review, code edits, documentation edits, repo-structure changes, or explicit requests to apply DOX/`AGENTS.md` workflow. Machine-local installed copies can mirror the repo-local skill for deployment or interactive use, but the versioned repo-local skill is the canonical Symphony copy.

The skill instructs Codex to:

- identify expected target paths from the user request, git state, review scope, or planned edits
- read the root `AGENTS.md` when present
- walk from repo root to each target path and read every applicable `AGENTS.md`
- treat the nearest applicable doc as the local contract
- preserve user changes and avoid unrelated rewrites
- update owning docs when meaningful contract, workflow, behavior, or structure changes occur
- report when docs are intentionally left unchanged
- use MemPalace only for recall or discovery when available
- treat missing, stale, or contradictory indexed child docs as documentation defects to fix or explicitly defer

## Symphony Behavior

Add a root `AGENTS.md` at the Symphony repository root. It should establish the repo-wide DOX contract and a child index that points to `elixir/AGENTS.md`.

Document `.codex/skills/dox/SKILL.md` in the root contract as the canonical repo-local DOX skill so future workflow changes are made in the versioned copy first.

Revise `elixir/AGENTS.md` so it remains the local contract for the Elixir orchestration service while fitting into the DOX hierarchy. Existing Elixir rules should be preserved.

Update `elixir/WORKFLOW.md` so Symphony-launched Codex agents follow the DOX chain in their per-issue workspaces before editing. This should be prompt guidance, not a new runtime dependency.

The workflow prompt must apply DOX before planning, read-only review, workpad updates, repo analysis, or edits. Missing Linear tooling must not lead to impossible Linear mutations: if Linear itself is unavailable, the agent reports `blocked: missing Linear tool/auth` in the final message and exits cleanly. Related skills such as `pull` and `land` remain available, but the Symphony unattended workflow controls if a skill asks for human input; agents must choose a safe autonomous fallback, documented pushback, or the blocked-access escape hatch instead of waiting indefinitely.

For app-touching changes, runtime validation should prefer `launch-app` and `github-pr-media`. If either capability is unavailable, the agent must use a repo-local validation command or documented manual runtime substitute when one exists; if no substitute exists and runtime validation is required, the blocked-access escape hatch applies.

## MemPalace Usage

MemPalace should be installed or wired separately when available. Recall scope should default to the current repository, current issue or task, and explicitly relevant local Codex skills or rules. Broader memory should be used only when the user asks for it. The DOX workflow can recommend mining:

- `C:\Users\starg\Documents\Codex\symphony`
- repo-local Codex skills under `.codex/skills` and installed local mirrors under `C:\Users\starg\.codex` or `C:\Users\starg\.agents` when relevant
- relevant session history where appropriate

Search results may suggest related files or decisions, but the agent must verify binding instructions by reading the actual workspace files.

Do not publish recalled content into Linear, PRs, issues, or durable docs unless it has been re-verified against current workspace files or the user explicitly asks to use that recalled source. Keep provenance for material memory-derived facts without copying private recalled content, using source class and verified workspace file references rather than private recalled text.

## Error Handling

If no root `AGENTS.md` exists, the agent proceeds with any path-local `AGENTS.md` files it finds and reports the missing root when relevant.

If a referenced child `AGENTS.md` is missing, stale, or contradictory, the agent treats that as a documentation defect and either fixes it during the closeout pass or reports why it was deferred.

If MemPalace is unavailable, the DOX workflow continues without semantic recall.

## Testing

Verification should cover:

- the repo-local Codex skill exists at `.codex/skills/dox/SKILL.md` and has valid `SKILL.md` front matter
- Symphony has a root `AGENTS.md`
- the Symphony root child index references `elixir/AGENTS.md`
- `elixir/AGENTS.md` preserves existing project-specific rules
- `WORKFLOW.md` instructs launched agents to follow the DOX chain and continue with path-local docs when a root `AGENTS.md` is absent
- `WORKFLOW.md` routes missing Linear tooling through the blocked-access path instead of asking a human
- `WORKFLOW.md` exits cleanly without issue/workpad mutation when Linear itself is unavailable
- app-touching validation has a defined fallback path when `launch-app` or `github-pr-media` is unavailable
- normal-path and missing-root dry runs of the DOX instructions are reviewed manually or covered by an equivalent prompt-loader/runtime check

Full Symphony gates are required for Elixir source changes and `WORKFLOW.md` prompt changes unless a narrower prompt-loader/runtime validation is added and documented in the same change. Documentation-only changes outside `WORKFLOW.md` can be verified with targeted file checks and git diff review.
