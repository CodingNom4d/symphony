# DOX and MemPalace Hybrid Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a deterministic DOX instruction workflow for local Codex and Symphony, with MemPalace reserved for semantic recall and discovery.

**Architecture:** Symphony gets a repo-local canonical `dox` skill that defines how to discover and apply `AGENTS.md` chains. Machine-local installed copies can mirror that skill for deployment or interactive use. Symphony also gets a root `AGENTS.md`, an updated `elixir/AGENTS.md`, and workflow prompt guidance so spawned agents follow the same deterministic instruction chain in per-issue workspaces.

**Tech Stack:** Markdown `AGENTS.md`, Codex native skills, Symphony `WORKFLOW.md`, PowerShell verification commands.

---

## Chunk 1: Repo-Local Codex DOX Skill

### Task 1: Create the DOX Skill

**Files:**
- Create: `C:\Users\starg\Documents\Codex\symphony\.codex\skills\dox\SKILL.md`
- Deployment mirror: `C:\Users\starg\.agents\skills\dox\SKILL.md`

- [x] **Step 1: Write the skill file**

Create the versioned repo-local Codex skill with valid front matter. The machine-local installed copy may mirror this file, but it is not the canonical Symphony source.

```markdown
---
name: dox
description: Use when planning, read-only reviewing, editing code or documentation, changing repository structure, or working in repositories that may contain AGENTS.md files; also use when applying DOX, AGENTS.md hierarchy, instruction-chain, repository-contract, or doc-closeout behavior.
---
```

Include instructions for:

- target path identification from user request, git state, and planned edits
- planning/read-only review/workpad sequencing before repo analysis or edits
- root-to-target `AGENTS.md` chain reading
- nearest-doc-wins conflict handling
- closeout doc update rules
- MemPalace as recall/discovery only
- memory provenance and publication guardrails
- stale or missing child `AGENTS.md` defect handling
- reporting intentionally unchanged docs

- [x] **Step 2: Verify the skill exists**

Run:

```powershell
Test-Path C:\Users\starg\Documents\Codex\symphony\.codex\skills\dox\SKILL.md
```

Expected: `True`

- [x] **Step 3: Verify skill front matter**

Run:

```powershell
Select-String -Path C:\Users\starg\Documents\Codex\symphony\.codex\skills\dox\SKILL.md -Pattern '^name: dox$','^description:'
```

Expected: both `name` and `description` lines are present.

## Chunk 2: Symphony DOX Contracts

### Task 2: Add Root Symphony Contract

**Files:**
- Create: `C:\Users\starg\Documents\Codex\symphony\AGENTS.md`

- [x] **Step 1: Create root `AGENTS.md`**

Create a concise root contract with these sections:

- Purpose
- Ownership
- Local Contracts
- Work Guidance
- Verification
- Child DOX Index

The Child DOX Index must point to `elixir/AGENTS.md` and describe it as the Elixir orchestration service contract.

Also document `.codex/skills/dox/SKILL.md` as the repo-local canonical DOX skill and note that machine-local installed copies are deployment mirrors.

- [x] **Step 2: Verify root child index**

Run:

```powershell
Select-String -Path C:\Users\starg\Documents\Codex\symphony\AGENTS.md -Pattern 'elixir/AGENTS.md','Child DOX Index'
```

Expected: both patterns are present.

### Task 3: Revise Elixir Contract

**Files:**
- Modify: `C:\Users\starg\Documents\Codex\symphony\elixir\AGENTS.md`

- [x] **Step 1: Preserve existing rules and reshape into DOX sections**

Keep existing Elixir environment, conventions, validation, required rules, PR requirements, and docs update policy. Reorganize them under DOX section headings:

- Purpose
- Ownership
- Local Contracts
- Work Guidance
- Verification
- Child DOX Index

The child index should state that there are no child `AGENTS.md` files yet, unless one is discovered before editing.

- [x] **Step 2: Verify existing quality gates remain**

Run:

```powershell
Select-String -Path C:\Users\starg\Documents\Codex\symphony\elixir\AGENTS.md -Pattern 'make all','mix specs.check','WORKFLOW.md','docs/logging.md'
```

Expected: all four patterns are present.

## Chunk 3: Symphony Workflow Prompt

### Task 4: Add DOX Startup Guidance

**Files:**
- Modify: `C:\Users\starg\Documents\Codex\symphony\elixir\WORKFLOW.md`

- [x] **Step 1: Add DOX instruction to `Instructions`**

Add a new instruction near the top of the `Instructions:` list:

```markdown
4. Before planning, reviewing, opening/updating the workpad, analyzing repo files, or editing files, apply the DOX workflow: read the repository root `AGENTS.md` when present, read every applicable child `AGENTS.md` from the repository root to each target path, follow the nearest local contract plus parent contracts, and perform a closeout docs pass after meaningful edits. If no root `AGENTS.md` exists, continue with any path-local `AGENTS.md` files you find and note the missing root only when relevant to the task.
5. Use MemPalace or semantic memory only for recall and discovery; scope recall to the current repository, current issue, and explicitly relevant local Codex skills or rules unless the user asks for broader memory. Binding instructions must come from files in the current workspace. Do not publish recalled content into Linear, PRs, issues, or durable docs unless it has been re-verified against current workspace files or the user explicitly asks to use that recalled source.
```

Renumber the existing later instruction if needed.

- [x] **Step 2: Verify workflow prompt guidance**

Run:

```powershell
Select-String -Path C:\Users\starg\Documents\Codex\symphony\elixir\WORKFLOW.md -Pattern 'DOX workflow','MemPalace','AGENTS.md'
```

Expected: all three patterns are present.

### Task 4.5: Fix Unattended Linear Tooling Fallback

**Files:**
- Modify: `C:\Users\starg\Documents\Codex\symphony\elixir\WORKFLOW.md`

- [x] **Step 1: Route missing Linear tooling through blocked access**

Replace any instruction to ask a human to configure Linear during an unattended run with a pointer to the blocked-access escape hatch.

If Linear itself is unavailable, the prompt must exit cleanly without attempting impossible issue or workpad mutations.

- [x] **Step 2: Verify no invalid ask-human fallback remains**

Run:

```powershell
Select-String -Path C:\Users\starg\Documents\Codex\symphony\elixir\WORKFLOW.md -Pattern 'ask the user to configure Linear'
```

Expected: no matches.

### Task 4.6: Add Unattended Related-Skill Override

**Files:**
- Modify: `C:\Users\starg\Documents\Codex\symphony\elixir\WORKFLOW.md`

- [x] **Step 1: Prevent indefinite human waits from related skills**

Document that `WORKFLOW.md` controls when related skills such as `pull` or `land` ask to wait for or ask a human. The agent should use the safest reversible action, documented pushback, or blocked-access escape hatch rather than waiting indefinitely.

- [x] **Step 2: Verify override wording**

Run:

```powershell
Select-String -Path C:\Users\starg\Documents\Codex\symphony\elixir\WORKFLOW.md -Pattern 'Symphony unattended override','do not wait indefinitely'
```

Expected: both patterns are present.

### Task 4.7: Define App Runtime Validation Fallback

**Files:**
- Modify: `C:\Users\starg\Documents\Codex\symphony\elixir\WORKFLOW.md`

- [x] **Step 1: Add fallback behavior**

Add an `App runtime validation` section requiring `launch-app` and `github-pr-media` when available, repo-local validation or documented manual runtime substitute when unavailable, and blocked-access only when app validation is required and no substitute exists.

- [x] **Step 2: Verify fallback wording**

Run:

```powershell
Select-String -Path C:\Users\starg\Documents\Codex\symphony\elixir\WORKFLOW.md -Pattern 'App runtime validation','launch-app','github-pr-media','repo-local validation command'
```

Expected: all patterns are present.

### Task 4.8: Tighten Memory Scope and Provenance

**Files:**
- Modify: `C:\Users\starg\Documents\Codex\symphony\elixir\WORKFLOW.md`
- Modify: `C:\Users\starg\Documents\Codex\symphony\AGENTS.md`
- Modify: `C:\Users\starg\Documents\Codex\symphony\docs\superpowers\specs\2026-06-12-dox-mempalace-hybrid-design.md`

- [x] **Step 1: Scope semantic recall and provenance**

Limit semantic recall to the current repository, current issue or task, and explicitly relevant local skills or rules unless the user asks for broader memory. Record material memory use as provenance only, without copying private recalled content.

- [x] **Step 2: Verify memory wording**

Run:

```powershell
Select-String -Path C:\Users\starg\Documents\Codex\symphony\AGENTS.md,C:\Users\starg\Documents\Codex\symphony\elixir\WORKFLOW.md,C:\Users\starg\Documents\Codex\symphony\docs\superpowers\specs\2026-06-12-dox-mempalace-hybrid-design.md -Pattern 'current repository','current issue','memory provenance','without copying private recalled content'
```

Expected: scoping and provenance wording are present.

### Task 4.9: Clarify Read-Only Review Coverage

**Files:**
- Modify: `C:\Users\starg\Documents\Codex\symphony\.codex\skills\dox\SKILL.md`
- Modify: `C:\Users\starg\Documents\Codex\symphony\docs\superpowers\specs\2026-06-12-dox-mempalace-hybrid-design.md`

- [x] **Step 1: Update skill trigger and heading**

Ensure the repo-local DOX skill front matter and workflow heading clearly include read-only review, not only planning or editing.

- [x] **Step 2: Verify skill heading**

Run:

```powershell
Select-String -Path C:\Users\starg\Documents\Codex\symphony\.codex\skills\dox\SKILL.md -Pattern 'read-only reviewing','Before Planning, Read-Only Review, or Editing'
```

Expected: both patterns are present.

## Chunk 4: Verification and Review

### Task 5: Validate Docs-Only Change

**Files:**
- Read: `C:\Users\starg\Documents\Codex\symphony\AGENTS.md`
- Read: `C:\Users\starg\Documents\Codex\symphony\elixir\AGENTS.md`
- Read: `C:\Users\starg\Documents\Codex\symphony\elixir\WORKFLOW.md`
- Read: `C:\Users\starg\Documents\Codex\symphony\.codex\skills\dox\SKILL.md`

- [x] **Step 1: Check git diff**

Run:

```powershell
git -C C:\Users\starg\Documents\Codex\symphony diff -- AGENTS.md elixir/AGENTS.md elixir/WORKFLOW.md docs/superpowers/specs/2026-06-12-dox-mempalace-hybrid-design.md docs/superpowers/plans/2026-06-12-dox-mempalace-hybrid.md
```

Expected: only DOX/MemPalace documentation and prompt changes.

- [x] **Step 2: Check repository status**

Run:

```powershell
git -C C:\Users\starg\Documents\Codex\symphony status --short
```

Expected: planned files are modified or untracked; pre-existing unrelated temp directory remains untouched.

- [x] **Step 3: Decide full gates**

Because this plan changes `WORKFLOW.md`, run the main quality gate unless a narrower prompt-loader/runtime validation is added and documented. Record any skipped gate with the exact reason and replacement evidence.

Verification note for this iteration: `make all` was attempted from PowerShell and Docker Desktop WSL, but `make`, `mix`, and `mise` were unavailable in the accessible environments. Replacement evidence is the documented prompt-level dry run plus static file checks and reviewer-panel review.

- [x] **Step 4: Manual DOX dry-run checks**

Review the prompt text against two scenarios:

- Normal path: root `AGENTS.md` and `elixir/AGENTS.md` are present for an `elixir/lib/...` edit.
- Missing-root path: root `AGENTS.md` is absent, but a path-local `AGENTS.md` exists.

Expected: both scenarios have a non-blocking path to continue.

- [x] **Step 5: Git-focused review loop**

Keep a Git-focused reviewer in the panel until clean. The reviewer should check branch hygiene, untracked-file risk, diff scope, and commit/PR readiness.

Git reviewer note: the second-pass Git reviewer found intended new repo files were untracked and the unrelated `elixir/UsersstargAppData...` temp tree should be excluded from staging.

### Task 5.5: Local Git Hygiene for Generated Temp Tree

**Files:**
- Modify: `C:\Users\starg\Documents\Codex\symphony\.git\info\exclude`

- [x] **Step 1: Exclude unrelated generated temp tree locally**

Add a local-only exclude pattern for `elixir/UsersstargAppData*ocalTemp/` so generated temp artifacts do not appear in status and cannot be accidentally staged.

- [x] **Step 2: Verify intended new files remain visible**

Run:

```powershell
git -C C:\Users\starg\Documents\Codex\symphony status --short --untracked-files=all
```

Expected: intended new repository docs remain visible and ready to stage; the unrelated temp tree is hidden.
