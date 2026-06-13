---
name: dox
description: Use when planning, read-only reviewing, editing code or documentation, changing repository structure, or working in repositories that may contain AGENTS.md files; also use when applying DOX, AGENTS.md hierarchy, instruction-chain, repository-contract, or doc-closeout behavior.
---

# DOX

## Core Principle

`AGENTS.md` files are deterministic workspace contracts. Semantic memory, search, and prior conversation context can help find relevant information, but binding instructions must be verified by reading files in the current workspace.

## Before Planning, Read-Only Review, or Editing

1. Identify every file or directory you expect to touch from the user request, git state, issue context, and planned edits.
2. Find the repository root for those paths.
3. Read the root `AGENTS.md` if it exists.
4. For each target path, walk from the repository root to that path and read every `AGENTS.md` encountered.
5. If a parent `AGENTS.md` lists a child `AGENTS.md` whose scope contains the target path, read that child and continue from there.
6. Treat the nearest applicable `AGENTS.md` as the local contract. Parent contracts still apply for broader rules.
7. If contracts conflict, the closer doc controls local details unless it tries to weaken a parent safety, quality, or DOX requirement.

Do not rely on memory for the applicable instruction chain. Re-read it in the current session before editing.

For read-only review, apply the same instruction-chain discovery before inspecting or judging repository files. If no edits are made, still report that closeout docs were intentionally left unchanged.

## Using MemPalace or Semantic Memory

Use MemPalace or other semantic memory only for recall and discovery, such as finding related decisions, likely owning docs, prior implementation notes, or terminology. Scope recall to the current repository, current task or issue, and explicitly relevant local Codex skills or rules unless the user asks for broader memory.

Do not use semantic search results as authority. After recall, verify instructions by opening the current workspace files.

Do not publish recalled content into issues, workpads, PRs, or docs unless it has been re-verified against current workspace files or the user explicitly asks to use that recalled source. When referencing recalled context, preserve enough provenance to identify where it came from.

If MemPalace is unavailable, continue with direct file and git inspection.

## After Meaningful Edits

Run a DOX closeout pass before reporting completion.

Update the nearest owning `AGENTS.md` when the change affects:

- purpose, scope, ownership, or responsibilities
- durable structure, contracts, workflows, or operating rules
- required inputs, outputs, permissions, constraints, side effects, or artifacts
- durable user preferences about behavior, communication, process, organization, or quality
- `AGENTS.md` creation, deletion, move, rename, or child-index contents

Update parent docs when parent-level structure, ownership, workflow, or child indexes change. Update child docs when parent changes alter local rules.

Small edits that do not change behavior or contracts may leave docs unchanged, but still run the closeout pass and report that docs were intentionally left unchanged.

## Child Indexes

Keep child indexes concise and operational. A parent index should name direct child `AGENTS.md` files and what each child owns.

If an indexed child `AGENTS.md` is missing, stale, outside its stated scope, or contradictory, treat that as a documentation defect. Fix it during closeout when it is in scope; otherwise report that it was intentionally deferred and why.

Do not recursively index an entire large repository unless the task requires it or an applicable contract explicitly demands it for the current work. If full indexing is deferred, say so and explain why.

## Closeout Checklist

- Re-check changed paths against the applicable `AGENTS.md` chain.
- Update nearest owning docs and affected parent or child indexes when needed.
- Remove stale or contradictory instructions.
- Run relevant verification for the changed surface.
- Report which docs changed, which docs were intentionally left unchanged, and why.
