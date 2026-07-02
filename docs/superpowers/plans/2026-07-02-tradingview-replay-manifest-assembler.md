# TradingView Replay Manifest Assembler Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the smallest pure offline replay manifest assembler on top of the COD-31 normalized TradingView signal envelope contract.

**Architecture:** Reuse the existing normalized signal-envelope fixtures as assembler inputs and pair them with local market-context row fixtures. Build one pure Elixir module that filters eligible rows by `available_at_utc` and staleness, keeps future or stale evidence outside `market_context.eligible_rows`, and emits the replay-manifest maps already documented in TradingView fixture JSON.

**Tech Stack:** Elixir, ExUnit, local JSON fixtures, `mix specs.check`, `make all`

---

## Chunk 1: Minimal Replay Manifest Scope

### Task 1: Trim the assembler to COD-32 scope

**Files:**
- Modify: `elixir/lib/symphony_elixir/tradingview/replay_manifest_assembler.ex`
- Modify: `elixir/test/symphony_elixir/tradingview/replay_manifest_assembler_test.exs`
- Modify if needed: `docs/tradingview/fixtures/replay-input.insufficient-data.missing_market.manifest.json`
- Keep as-is unless needed: `elixir/test/fixtures/tradingview_replay_manifest_assembler/accepted_context_rows.json`
- Keep as-is unless needed: `elixir/test/fixtures/tradingview_replay_manifest_assembler/insufficient_context_rows.json`

- [x] **Step 1: Reduce the tests to the two required fixture paths**

Keep one accepted replay-path test and one insufficient-context test. Remove extra alias-resolution, timing-order, and tie-break coverage that is outside the ticket scope.

- [x] **Step 2: Run the focused replay-manifest tests for the intended scope**

Run: `cd elixir && mix test test/symphony_elixir/tradingview/replay_manifest_assembler_test.exs`
Observed: pass after narrowing the module and fixture contract to the two COD-32 paths.

- [x] **Step 3: Reduce the implementation to the smallest contract-compatible behavior**

Keep:
- pure `assemble/2`
- signal-envelope fixture mapping only for the two fixture aliases used by COD-32
- as-of filtering by `available_at_utc <= decision_time`
- staleness filtering against the fixed threshold
- audit-only future/stale evidence outside `market_context.eligible_rows`

Remove:
- support code that only exists for out-of-scope fixture aliases
- behavior justified only by removed tests

- [x] **Step 4: Re-run the focused replay-manifest tests**

Run: `cd elixir && mix test test/symphony_elixir/tradingview/replay_manifest_assembler_test.exs`
Expected: 3 tests, 0 failures.

### Task 2: Run required verification

**Files:**
- No additional source changes expected

- [x] **Step 1: Run the TradingView normalizer and replay-manifest tests together**

Run: `cd elixir && mix test test/symphony_elixir/tradingview/signal_envelope_normalizer_test.exs test/symphony_elixir/tradingview/replay_manifest_assembler_test.exs`
Expected: both fixture-contract surfaces pass together.

- [x] **Step 2: Run the TradingView fixture guardrail test**

Run: `cd elixir && mix test test/symphony_elixir/boundary_guardrails_tradingview_fixture_test.exs`
Expected: pass.

- [x] **Step 3: Run guardrail checks**

Run: `cd elixir && mix guardrails.check`
Expected: pass.

- [x] **Step 4: Run required spec checks**

Run: `cd elixir && mix specs.check`
Expected: pass.

- [x] **Step 5: Run the main quality gate**

Run: `cd elixir && make all`
Expected: pass.

Status: completed in the current workspace with the replay assembler, local fixtures, fixture guardrails, `mix specs.check`, and `make all` all passing.
