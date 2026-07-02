# TradingView Signal Envelope Normalizer Implementation Plan

> **For agentic workers:** REQUIRED: Use superpowers:subagent-driven-development (if subagents available) or superpowers:executing-plans to implement this plan. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add the smallest pure offline TradingView signal envelope normalizer that deterministically maps fixture or operational-row-shaped inputs into the COD-29 checkpoint envelope without reading replay context, writing storage, or introducing live/private trading behavior.

**Architecture:** Introduce one pure Elixir module under `SymphonyElixir.Tradingview` that accepts map inputs and returns a normalized canonical envelope or fail-closed rejection result. Keep fixture loading and assertions in a focused test module; keep guardrail validation separate and unchanged unless a new output key requires explicit protection.

**Tech Stack:** Elixir 1.19, ExUnit, Jason, standard library hashing and datetime parsing

---

## Chunk 1: Contract and TDD Skeleton

### Task 1: Create the failing normalizer tests

**Files:**
- Create: `elixir/test/symphony_elixir/tradingview/signal_envelope_normalizer_test.exs`
- Create: `elixir/test/fixtures/tradingview_signal_envelope_normalizer/accepted_input.json`
- Create: `elixir/test/fixtures/tradingview_signal_envelope_normalizer/duplicate_input.json`
- Create: `elixir/test/fixtures/tradingview_signal_envelope_normalizer/rejected_secret_input.json`
- Create: `elixir/test/fixtures/tradingview_signal_envelope_normalizer/legacy_unmapped_input.json`
- Test: `elixir/test/symphony_elixir/tradingview/signal_envelope_normalizer_test.exs`

- [ ] **Step 1: Write the failing accepted-path test**

```elixir
test "normalizes an accepted fixture input deterministically" do
  input = fixture!("accepted_input.json")

  assert {:ok, normalized} = SignalEnvelopeNormalizer.normalize(input)
  assert {:ok, normalized_again} = SignalEnvelopeNormalizer.normalize(input)
  assert normalized == normalized_again
end
```

- [ ] **Step 2: Run the accepted-path test to verify it fails**

Run: `mix test test/symphony_elixir/tradingview/signal_envelope_normalizer_test.exs --only accepted`
Expected: FAIL because `SymphonyElixir.Tradingview.SignalEnvelopeNormalizer` does not exist yet

- [ ] **Step 3: Add failing duplicate, rejection, legacy, and purity tests**

```elixir
test "same canonical tuple yields the same idempotency hash" do
  left = fixture!("accepted_input.json")
  right = fixture!("duplicate_input.json")

  assert {:ok, normalized_left} = SignalEnvelopeNormalizer.normalize(left)
  assert {:ok, normalized_right} = SignalEnvelopeNormalizer.normalize(right)
  assert normalized_left.signal_idempotency_hash == normalized_right.signal_idempotency_hash
end

test "rejects secret-like payloads without retaining unsafe values" do
  input = fixture!("rejected_secret_input.json")

  assert {:error, normalized} = SignalEnvelopeNormalizer.normalize(input)
  refute inspect(normalized) =~ "api_key"
end

test "marks non-transformable rows as legacy_unmapped" do
  input = fixture!("legacy_unmapped_input.json")

  assert {:ok, normalized} = SignalEnvelopeNormalizer.normalize(input)
  assert normalized.validation_status == "legacy_unmapped"
  assert normalized.signal_idempotency_hash == nil
end

test "does not read replay or post-decision context fields" do
  input =
    fixture!("accepted_input.json")
    |> Map.put("post_decision_context", %{"market_context" => %{"source" => "should-be-ignored"}})

  assert {:ok, normalized} = SignalEnvelopeNormalizer.normalize(input)
  refute Map.has_key?(normalized, :post_decision_context)
end
```

- [ ] **Step 4: Run the full normalizer test file to verify it fails for the right reason**

Run: `mix test test/symphony_elixir/tradingview/signal_envelope_normalizer_test.exs`
Expected: FAIL with undefined module or function errors for the new normalizer

## Chunk 2: Minimal Implementation

### Task 2: Implement the pure normalizer

**Files:**
- Create: `elixir/lib/symphony_elixir/tradingview/signal_envelope_normalizer.ex`
- Modify: `elixir/test/symphony_elixir/tradingview/signal_envelope_normalizer_test.exs`
- Test: `elixir/test/symphony_elixir/tradingview/signal_envelope_normalizer_test.exs`

- [ ] **Step 1: Add the minimal module and public API**

```elixir
defmodule SymphonyElixir.Tradingview.SignalEnvelopeNormalizer do
  @spec normalize(map()) :: {:ok, map()} | {:error, map()}
  def normalize(input) when is_map(input) do
  end
end
```

- [ ] **Step 2: Implement deterministic field derivation**

```elixir
# Derive:
# - signal_schema_version
# - payload_hash
# - observed_at_utc / available_at_utc
# - source symbol and canonical instrument
# - intended side
# - provenance refs
# - validation status and reason
# - signal_idempotency_hash from the checkpoint tuple
```

- [ ] **Step 3: Implement fail-closed rejection and legacy handling**

```elixir
# Reject malformed, secret-like, or oversize payloads.
# Return only the allowed retained fields for rejected rows.
# Return legacy_unmapped when required canonical fields cannot be derived deterministically.
```

- [ ] **Step 4: Run the normalizer test file to verify it passes**

Run: `mix test test/symphony_elixir/tradingview/signal_envelope_normalizer_test.exs`
Expected: PASS

## Chunk 3: Guardrails and Focused Validation

### Task 3: Confirm the new code preserves dry-run guardrails

**Files:**
- Modify: `elixir/test/symphony_elixir/boundary_guardrails_tradingview_fixture_test.exs` only if a new output-key guardrail assertion is needed
- Test: `elixir/test/symphony_elixir/boundary_guardrails_tradingview_fixture_test.exs`

- [ ] **Step 1: Add a focused guardrail assertion only if the new output shape creates a real gap**

```elixir
# Prefer leaving guardrail code untouched.
# Add one targeted assertion if the normalizer introduces a key-shape risk not already covered.
```

- [ ] **Step 2: Run the TradingView guardrail test**

Run: `mix test test/symphony_elixir/boundary_guardrails_tradingview_fixture_test.exs`
Expected: PASS

- [ ] **Step 3: Run specs and the main quality gate**

Run: `mix specs.check`
Expected: PASS

Run: `make all`
Expected: PASS
