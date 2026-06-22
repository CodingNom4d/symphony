# TradingView Signal Envelope Checkpoint

Status: draft checkpoint for COD-29  
Scope: dry-run/public-data only  
Applies to: future TradingView research export, replay input generation, enrichment, and backtest preparation  
Does not authorize: execution, PnL claims, live trading, private exchange surfaces, new listeners, or raw request retention

## 1. Purpose

This checkpoint defines the canonical TradingView signal envelope and the market-context contract that later dry-run research and replay work must use.

This document is intentionally a mapping contract, not a second storage model. The repository already has operational webhook signal storage. Research, replay, enrichment, and export work must map from that shipped operational storage into the canonical envelope defined here. No later issue may introduce a parallel research-only signal schema unless it also introduces an explicit migration or mapping contract back to the operational rows.

## 2. Inputs And Boundaries

The source repository snapshot available to this isolated workspace does not include the TradingView operational schema files themselves. This checkpoint therefore anchors its normative mapping to the shipped operational row and lineage fields named in COD-29:

- `tradingview_signals.received_at`
- redacted `payload_json`
- `strategy_id`
- `strategy_version`
- `config_version_id`
- `signal_provenance`
- `decision_provenance`

Those names are treated as required compatibility targets from COD-29, not as re-verified schema proof from this workspace snapshot. Later implementation work must verify the exact shipped schema and update this document in the same change if any name or persistence detail differs. If later code discovery shows additional shipped operational columns, they may extend this mapping but must not weaken it.

This checkpoint also inherits the repository dry-run/public-data boundary enforced for future governed TradingView paths under `docs/tradingview` and replay/backtest paths. In particular:

- no private or authenticated exchange surfaces
- no raw request body retention by default
- no secret-like header, query-string, cookie, or webhook-secret persistence
- no listeners, schedulers, daemons, or execution imports introduced by replay/backtest work

Those boundary expectations align with `/source/repo/elixir/lib/symphony_elixir/boundary_guardrails.ex` and `/source/repo/docs/ndax_public_capability_gate.md`.

## 3. Canonical Envelope

### 3.1 Record identity

Each normalized signal row MUST expose:

| Field | Required | Type | Meaning | Derivation |
| --- | --- | --- | --- | --- |
| `signal_schema_version` | yes | string | Envelope contract version | Fixed literal for this checkpoint: `tv.signal-envelope.v1` |
| `signal_idempotency_hash` | yes | nullable string | Stable dedupe key for the normalized signal when canonical fields are derivable | SHA-256 of canonical tuple defined below; null only for rejected or legacy-unmapped rows that cannot produce the canonical tuple safely |
| `operational_signal_ref` | yes | object | Pointer back to shipped operational storage | Internal normalized rows may identify the original operational row primary key or durable row locator; exported manifests and fixtures must use only opaque aliases |
| `payload_hash` | yes | string | Hash of the retained redacted payload representation | SHA-256 of canonicalized redacted JSON |

The canonical tuple for `signal_idempotency_hash` is:

`strategy_id | strategy_version | config_version_id | canonical_instrument_id | intended_side | source_event_time_utc_or_null | payload_hash`

If the operational store exposes a durable row id, that id remains the authoritative row locator. The idempotency hash is for duplicate behavior, replay dedupe, and export stability. Rows that cannot safely derive the canonical tuple remain addressable only by the operational row locator and are never eligible for cross-row replay dedupe.

### 3.2 Canonical signal fields

| Field | Required | Nullable | Description | Source / rule |
| --- | --- | --- | --- | --- |
| `canonical_instrument_id` | yes | status-dependent | Canonical instrument identity used by replay/context joins | Required and non-null for replay-eligible rows; null only for `rejected` or `legacy_unmapped` rows where deterministic mapping failed |
| `source_symbol` | yes | status-dependent | Raw symbol text after redaction-safe normalization | Required and non-null when safely present; null only when absent after redaction or unavailable for `legacy_unmapped` rows |
| `instrument_source` | yes | no | Origin naming domain for symbol mapping | For this checkpoint use `tradingview` for signal origin; market-context source is stored separately |
| `intended_side` | yes | status-dependent | Canonical action/side intent | Required and non-null for replay-eligible rows; null only for `rejected` or `legacy_unmapped` rows where deterministic action normalization failed |
| `source_event_time_utc` | yes | yes | TradingView alert timestamp if present and parseable | From payload; null only when absent |
| `observed_at_utc` | yes | no | Time the operational system observed the signal | Mapped from `tradingview_signals.received_at` |
| `available_at_utc` | yes | no | Earliest time replay/export may treat the signal as visible | Equals `observed_at_utc` for this checkpoint |
| `finalized_at_utc` | yes | yes | Time after which the normalized signal row is immutable for a dataset version | Null for operational rows until dataset/export materialization |
| `validation_status` | yes | no | `accepted`, `rejected`, or `legacy_unmapped` | Set by normalization rules below |
| `validation_reason_code` | yes | yes | Canonical reason code when not accepted or when accepted with persisted operational reason lineage | Mapped by the reason matrix |
| `validation_failure_detail` | yes | yes | Minimal non-sensitive explanation | Must not include raw payload values or secrets |
| `signal_provenance_ref` | yes | yes | Required lineage handle into current signal provenance storage | Carry forward shipped `signal_provenance` linkage internally; exported artifacts must use opaque aliases only |
| `decision_provenance_ref` | yes | yes | Required lineage handle into current decision provenance storage | Carry forward shipped `decision_provenance` linkage internally; exported artifacts must use opaque aliases only |
| `strategy_id` | yes | no | Strategy lineage key | Direct mapping |
| `strategy_version` | yes | no | Strategy version lineage key | Direct mapping |
| `config_version_id` | yes | no | Config lineage key | Direct mapping |

### 3.3 Required normalization rules

Normalization MUST:

- preserve the operational row as source of truth
- derive the canonical envelope deterministically from the operational row plus shipped lineage rows
- fail closed when required fields cannot be derived safely
- never store the non-redacted original request body by default
- never treat `nearest_quote_after` as strategy input

Normalization MUST NOT:

- invent substitute market context
- infer unavailable timestamps from future data
- backfill missing sensitive values from logs or memory
- create a research-only shadow schema without a declared mapping layer

## 4. Field-By-Field Mapping From Operational Rows

The checkpoint mapping is defined per normalized signal row:

| Canonical field | Operational source | Rule |
| --- | --- | --- |
| `operational_signal_ref` | operational TradingView signal row id or stable locator | Required internally; later implementation must use the shipped row identity, not a synthetic research id. Exported manifests and fixtures must replace direct locators with opaque fixture aliases. |
| `observed_at_utc` | `tradingview_signals.received_at` | Direct UTC mapping |
| `available_at_utc` | `tradingview_signals.received_at` | Direct mapping at checkpoint stage |
| `source_event_time_utc` | redacted `payload_json` | Parse TradingView alert/source timestamp if present; else null |
| `source_symbol` | redacted `payload_json` | Extract symbol/ticker/instrument field per payload parser |
| `canonical_instrument_id` | redacted `payload_json` plus shipped symbol/instrument mapping contract | Required for export/replay; if mapping missing, row is not exportable |
| `intended_side` | redacted `payload_json` plus shipped action normalization contract | Required for export/replay; if normalization missing, row is not exportable |
| `payload_hash` | redacted `payload_json` | SHA-256 of canonicalized redacted JSON bytes |
| `strategy_id` | `strategy_id` | Direct mapping |
| `strategy_version` | `strategy_version` | Direct mapping |
| `config_version_id` | `config_version_id` | Direct mapping |
| `signal_provenance_ref` | `signal_provenance` | Carry forward lineage handle or row reference internally; export only an opaque alias |
| `decision_provenance_ref` | `decision_provenance` | Carry forward lineage handle or row reference internally; export only an opaque alias |
| `validation_status` | operational validation output plus checkpoint rules | Preserve accepted/rejected intent; use `legacy_unmapped` when the canonical mapping cannot be completed deterministically |
| `validation_reason_code` | operational persisted reason code | Preserve current operational code when present; otherwise apply checkpoint reason matrix |
| `validation_failure_detail` | derived | Minimal redaction-safe text only |
| `finalized_at_utc` | derived during dataset/export build | Null in operational read path until dataset materialization freezes the row |
| `signal_idempotency_hash` | derived from mapped fields | Computed only after canonical field derivation succeeds |

### 4.1 No parallel schema rule

Research/export/replay code MAY materialize:

- a compatibility view
- a deterministic transform job
- a dataset manifest
- immutable exported fixtures

Research/export/replay code MUST NOT materialize:

- a second signal schema with different business meaning and no mapping contract
- a replay-only signal table that omits operational lineage
- a shadow payload store that keeps raw rejected bodies

## 5. Legacy Row Handling

Legacy operational rows fall into exactly two buckets.

### 5.1 Deterministically transformable

A legacy row is transformable if all of the following can be derived without guessing:

- operational row identity
- `observed_at_utc` from `tradingview_signals.received_at`
- redacted payload JSON
- `strategy_id`
- `strategy_version`
- `config_version_id`
- canonical instrument mapping
- canonical intended side
- payload hash

For transformable rows:

- generate `payload_hash` from the redacted payload
- derive `source_event_time_utc` if present and parseable
- compute `signal_idempotency_hash`
- set `validation_status` to `accepted` or `rejected` according to existing operational intent and the reason matrix

### 5.2 Non-transformable

A legacy row is non-transformable if any required canonical field cannot be derived deterministically. Those rows MUST:

- remain readable through the operational path
- be marked `validation_status = legacy_unmapped`
- be non-exportable
- be non-replayable
- keep only minimal non-sensitive failure detail

No later implementation may silently coerce `legacy_unmapped` rows into replay fixtures.

## 6. Duplicate Behavior

Duplicate detection is defined strictly by `signal_idempotency_hash` for replay-eligible normalized rows.

Rules:

- same hash and same operational row locator: same normalized row
- same hash and different operational row locator: duplicate signal instance
- null hash: no cross-row duplicate judgment is permitted; the row remains identifiable only by `operational_signal_ref`
- duplicates may be retained for audit, but replay/export MUST dedupe by idempotency hash unless a later issue explicitly models duplicate-observation analysis

## 7. Reason-Code Matrix

The reason codes named in COD-29 are treated here as required compatibility targets for later implementation verification. Replay and fixture labels add a second classification layer instead of rewriting those reason names away.

| Canonical reason code | Source status | Replay / fixture label | Notes |
| --- | --- | --- | --- |
| `missing_market` | compatibility target from COD-29 | `insufficient_data` | No usable context rows at or before decision time |
| `stale_quote` | compatibility target from COD-29 | `stale_context` | Quote exists but violates staleness threshold |
| `stale_signal` | compatibility target from COD-29 | `stale_context` | Signal itself is too old for the decision horizon |
| `future_signal` | compatibility target from COD-29 | `future_data_rejected` | Signal source timestamp is later than permitted decision reconstruction time |
| `future_quote` | compatibility target from COD-29 | `future_data_rejected` | Quote/context row is available only after decision time |
| `accepted_replay` | compatibility target from COD-29 | `accepted_replay` | Accepted under replay-only evaluation |
| `invalid_payload` | new checkpoint code | `invalid_payload` | Payload missing required fields, malformed, secret-like, or oversize |
| `legacy_unmapped` | new checkpoint code | `insufficient_data` | Operational row readable but not exportable/replayable without deterministic transform |

Rules:

- preserve existing operational reason codes exactly when they are confirmed in shipped storage
- do not collapse current reasons into generic `invalid`
- replay labels are derivative and may group multiple canonical reason codes
- fixture names MUST carry both the replay label and the canonical reason code when applicable

## 8. Redaction And Rejection

### 8.1 Redaction

Field-level redaction MUST happen before payload hashing and before any export fixture write.

Rejected or persisted rows MUST NOT retain:

- raw request body
- webhook secrets or signatures
- request headers
- cookies
- query strings
- credential-like values
- oversize secret-like free text

Rejected rows still expose the required envelope keys so downstream readers can parse a single envelope shape. This list constrains non-null retained content for rejected rows; required keys whose values cannot be derived safely MUST remain null.

Allowed non-null retained content for rejected rows:

- `signal_schema_version`
- `payload_hash`
- `instrument_source` when it is a fixed non-sensitive source literal such as `tradingview`
- opaque operational row alias in exported artifacts
- `observed_at_utc`
- `available_at_utc`
- `finalized_at_utc` only when a rejected row is part of an immutable dataset/export materialization
- `validation_status`
- `validation_reason_code`
- minimal non-sensitive failure detail
- redaction-safe strategy/config lineage identifiers
- opaque signal or decision provenance aliases when they exist

### 8.2 Rejection rules

Rows MUST be rejected with `invalid_payload` when:

- required action/side cannot be derived
- symbol/instrument field is absent after redaction
- payload JSON is malformed
- payload contains secret-like material, even if the sensitive field could be isolated or redacted
- payload exceeds the later implementation size threshold for safe offline retention

If rejection occurs, the system MUST:

- hash only the retained redacted representation
- discard the original unsafe content
- retain no secret-bearing field values in normalized rows, exports, manifests, or fixtures

## 9. Replay Fixture Categories And Failure Labels

Offline fixtures for later implementation and tests MUST use the following categories:

| Fixture category | Required label(s) | Meaning |
| --- | --- | --- |
| accepted signal | `accepted_replay` | Signal normalized and context-complete under as-of rules |
| invalid signal | `invalid_payload` | Payload rejected before context lookup |
| stale context | `stale_context` | Context rows existed but failed staleness checks |
| insufficient context | `insufficient_data` | Context rows absent or legacy lineage incomplete |
| future data rejected | `future_data_rejected` | Needed signal/context data existed only after `decision_time` |

Mapping expectations:

- `missing_market` -> `insufficient_data`
- `stale_quote` -> `stale_context`
- `stale_signal` -> `stale_context`
- `future_signal` -> `future_data_rejected`
- `future_quote` -> `future_data_rejected`

## 10. Timestamp Semantics

All timestamps are UTC.

### 10.1 Signal records

| Field | Precedence | Meaning |
| --- | --- | --- |
| `source_event_time_utc` | payload timestamp if present and parseable; else null | TradingView-origin event time |
| `observed_at_utc` | `tradingview_signals.received_at` | Time the operational system first observed the signal |
| `available_at_utc` | `observed_at_utc` unless a later transform explicitly delays visibility | Earliest replay/export visibility |
| `finalized_at_utc` | dataset/export materialization time | Freeze time for immutable dataset rows |

### 10.2 Market-context records

| Field | Precedence | Meaning |
| --- | --- | --- |
| `source_event_time_utc` | provider event timestamp | Origin event time for quote/trade/bar |
| `observed_at_utc` | local capture/ingest observation time | When the system saw the context row |
| `available_at_utc` | first durable visibility time | Earliest allowed replay visibility |
| `finalized_at_utc` | only when the record family has a completion boundary | For bars, null until the bar is closed/final |
| `bar_time` | provider-supplied bar timestamp when present | Provider-native bar anchor |
| `interval_start_utc` | explicit interval start if known; else derived from bar orientation and interval | Inclusive start of the bar interval |
| `interval_end_utc` | explicit interval end if known; else derived | Exclusive or closing boundary declared in dataset metadata |

### 10.3 Decision records

`decision_time` is the replay/backtest reconstruction timestamp at which strategy logic is evaluated.

Rules:

- strategy input rows MUST satisfy `available_at_utc <= decision_time`
- late-arriving rows MAY appear in audit output but MUST NOT alter the reconstructed decision if their `available_at_utc` exceeds `decision_time`
- out-of-order arrivals are reconstructed by `available_at_utc`, not by source timestamp alone

## 11. Context-Symbol Alignment Contract

Every replayable dataset or fixture MUST declare:

- `canonical_instrument_id`
- market-data `source`
- `timezone`
- `session_calendar`
- `bar_orientation`
- `staleness_threshold`
- `as_of_alignment`

### 11.1 Required meanings

| Field | Meaning |
| --- | --- |
| `canonical_instrument_id` | Stable join key used between signal and context streams |
| `source` | Market-data source family used for replay context |
| `timezone` | Timezone used to interpret session boundaries |
| `session_calendar` | Trading-session calendar identifier or ruleset |
| `bar_orientation` | Whether bars are start-anchored, end-anchored, or provider-native |
| `staleness_threshold` | Maximum age tolerated for each required context family at decision time |
| `as_of_alignment` | Metadata describing the exact available-at cutoff and only the matched replay-eligible context row ids |

Context features fail closed unless all required alignment metadata is present.

## 12. As-Of Rule And Audit-Only Evidence

The as-of rule is mandatory:

`replay/backtest decisions may read only rows with available_at_utc <= decision_time`

Additional rules:

- `nearest_quote_after` may be stored only as audit or enrichment evidence
- `nearest_quote_after` MUST NOT be used as strategy input
- `nearest_quote_after` MUST live outside `as_of_alignment` in a clearly audit-only field
- post-decision market data MUST NOT change the simulated decision outcome
- late revisions may be retained for audit but do not rewrite prior decisions

## 13. Dataset Manifests And Replay Inputs

Every exported dataset manifest or replay input MUST carry:

- `signal_schema_version`
- `context_contract_version`
- `decision_time_basis`
- `decision_time_offset` or equivalent explicit horizon when `decision_time` differs from the signal visibility timestamp
- `available_at_rule`
- `signal_ref`
- `signal_provenance_ref`
- `decision_provenance_ref`
- declared record families and sources
- fixture category / failure label
- row counts
- lineage references for signal and decision provenance
- inline timing evidence for each replay-eligible context row used by the fixture

Replay inputs MUST include enough metadata to prove:

- which normalized signal row was evaluated
- which context rows were eligible under `available_at_utc <= decision_time`
- the `available_at_utc` and source event timestamps for those eligible rows
- whether the signal was accepted, rejected, or non-replayable

`signal_ref` in exported manifests MUST be an object that anchors to an opaque normalized-signal alias and, when the fixture set includes file artifacts, the corresponding signal-envelope fixture filename. A bare replay-only string is not sufficient.

`market_context.eligible_rows` contains only strategy-eligible context rows that both satisfy `available_at_utc <= decision_time` and pass the declared context validity rules such as staleness. As-of-visible but strategy-ineligible rows, including stale quotes and future-only evidence, MUST live under audit-only evidence and must not appear in `eligible_rows`.

Audit-only evidence such as `nearest_quote_after` or stale context candidates MUST live outside the replay-eligibility set.

## 14. Read-Path Compatibility Expectations

This checkpoint does not require replacing operational storage.

Required compatibility behavior:

- existing operational DB rows remain readable
- existing operational fixtures remain readable
- normalization is additive and mapping-based
- non-transformable legacy rows remain readable but non-exportable and non-replayable

The offline fixture set for this checkpoint is expected to include:

- one accepted replay example
- one invalid payload example
- one stale context example
- one insufficient data example
- one future data rejected example
- one legacy-unmapped compatibility example
- a corresponding normalized signal-envelope fixture for every replay manifest signal reference

This checkpoint intentionally defers any destructive migration.

## 15. Replay Output Claims

Pre-execution replay outputs are:

- non-executable
- non-order-routing
- non-performance-claim artifacts

They MUST NOT claim:

- realized or simulated PnL as validated performance
- win rate, Sharpe, or fill-quality performance conclusions
- trade execution readiness

## 16. Review Panel Gate

Before later implementation issues start, reviewers must confirm:

- dry-run/public-data boundaries remain intact
- no private surfaces or credentials are introduced
- no parallel schema drift was introduced
- legacy-row handling is deterministic
- fixtures are offline and file-based
- replay stays as-of safe
- outputs make no performance claims

## 17. Open Validation Dependency

Because the current isolated workspace does not contain the operational TradingView schema files, later implementation must verify this checkpoint against the shipped schema definitions before code lands. If any shipped column names differ from the field names named in COD-29, that later issue must update this document in the same change and preserve the no-parallel-schema rule.
