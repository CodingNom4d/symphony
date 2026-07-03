# Dependency Security Advisory Remediation Notes

## Scope

COD-33 remediates dependency security advisories surfaced by `mix deps.get` during the COD-32 verification gate.

This change is dependency-only and does not add runtime behavior, network surfaces, schedulers, credential handling, or TradingView/exchange functionality.

## Advisory Discovery

Before the lockfile update, `mix deps.get` reported advisories for these locked packages:

- `bandit` 1.10.3
- `decimal` 2.3.0
- `mint` 1.7.1
- `phoenix` 1.8.4
- `plug` 1.19.1
- `req` 0.5.17

## Remediation

`mix deps.update --all` updated the vulnerable package set and related transitive dependencies:

- `bandit` 1.10.3 -> 1.12.0
- `decimal` 2.3.0 -> 3.1.1
- `mint` 1.7.1 -> 1.9.0
- `phoenix` 1.8.4 -> 1.8.8
- `plug` 1.19.1 -> 1.20.2
- `req` 0.5.17 -> 0.6.2

Follow-on dependency updates included `ecto`, `finch`, `solid`, `phoenix_live_view`, `telemetry`, `thousand_island`, and test/dev tooling packages required by the resolver.

## Compatibility Adjustment

The Ecto 3.14.0 update changed the behavior of the existing `validate_required/2` check for `codex.command` when the schema preserves empty strings with `empty_values: []`.

To preserve the existing workflow contract, `SymphonyElixir.Config.Schema.Codex.changeset/2` now explicitly rejects only an empty command string (`""`) while continuing to accept whitespace-only command strings. This matches the existing regression coverage in `test/symphony_elixir/core_test.exs`.

## Post-Update State

After the lockfile update, `mix deps.get` no longer reports vulnerable packages.

`mix hex.outdated --all` still reports these packages as update constrained:

- `elixir_make` 0.9.0, latest 0.10.0
- `phoenix_live_view` 1.1.32, latest 1.2.5
- `websock_adapter` 0.5.9, latest 0.6.0

Those constrained packages did not appear in the post-update advisory output and are not expanded in this issue.

## Required Verification

- `cd elixir && mix deps.get`
- `cd elixir && mix hex.outdated --all`
- `cd elixir && mix test test/symphony_elixir/core_test.exs`
- `cd elixir && make all`

## Verification Evidence

- `mix test test/symphony_elixir/core_test.exs --trace`: 47 tests, 0 failures.
- `mix deps.get`: completed without vulnerable package advisory output after the lockfile update.
- `mix hex.outdated --all`: all advisory-remediated packages were up to date; only `elixir_make`, `phoenix_live_view`, and `websock_adapter` remained resolver-constrained without advisory output.
- `make all`: setup, build, format check, lint, coverage, and Dialyzer passed; 333 tests, 0 failures, 2 skipped, total coverage 100%, Dialyzer total errors 0.

## Review Notes

- Dependency review found no blocking issues.
- Residual watch area: `req` 0.6.2 is the highest-risk runtime upgrade because it changed some HTTP defaults across the 0.6 series; existing Linear client and integration coverage passed under the full gate.
