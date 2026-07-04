defmodule SymphonyElixir.BoundaryGuardrailsTradingviewFixtureTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.BoundaryGuardrails

  test "accepts a clean tradingview fixture set" do
    in_temp_project(fn root ->
      write_fixture_set!(root)

      findings =
        BoundaryGuardrails.findings(root)
        |> Enum.filter(&String.starts_with?(&1.path, "docs/tradingview/"))

      assert findings == []
    end)
  end

  test "rejects a bare string signal_ref in replay manifests" do
    in_temp_project(fn root ->
      write_fixture_set!(root, signal_ref: "signal_fixture_001")

      assert_rule(root, :signal_ref_shape)
    end)
  end

  test "rejects a replay manifest that references a missing envelope fixture" do
    in_temp_project(fn root ->
      write_fixture_set!(
        root,
        signal_ref: %{
          "fixture_alias" => "signal_fixture_001",
          "envelope_fixture" => "signal-envelope.missing.json"
        }
      )

      assert_rule(root, :missing_envelope_fixture)
    end)
  end

  test "rejects replay manifests that reference envelope fixtures outside the fixture directory" do
    in_temp_project(fn root ->
      File.mkdir_p!(Path.join(root, "docs/tradingview/other"))

      Path.join(root, "docs/tradingview/other/outside.json")
      |> File.write!(
        Jason.encode_to_iodata!(%{
          "signal_schema_version" => "tv.signal-envelope.v1",
          "operational_signal_ref" => %{"alias" => "signal_fixture_001"}
        })
      )

      write_fixture_set!(
        root,
        signal_ref: %{
          "fixture_alias" => "signal_fixture_001",
          "envelope_fixture" => "../other/outside.json"
        }
      )

      assert_rule(root, :envelope_fixture_path)
    end)
  end

  test "rejects a replay manifest whose alias differs from the signal-envelope alias" do
    in_temp_project(fn root ->
      write_fixture_set!(
        root,
        signal_ref: %{
          "fixture_alias" => "signal_fixture_999",
          "envelope_fixture" => "signal-envelope.valid.minimal.json"
        }
      )

      assert_rule(root, :signal_ref_alias_mismatch)
    end)
  end

  test "rejects a replay manifest whose envelope fixture is not a JSON object" do
    in_temp_project(fn root ->
      write_fixture_set!(root)

      Path.join(root, "docs/tradingview/fixtures/signal-envelope.valid.minimal.json")
      |> File.write!(Jason.encode_to_iodata!([]))

      assert_rule(root, :signal_ref_alias_mismatch)
      assert_message(root, "must be a JSON object")
    end)
  end

  test "rejects replay manifest signal_ref objects that include direct locator fields" do
    in_temp_project(fn root ->
      write_fixture_set!(
        root,
        signal_ref: %{
          "fixture_alias" => "signal_fixture_001",
          "envelope_fixture" => "signal-envelope.valid.minimal.json",
          "row_id" => "operational-row-42"
        }
      )

      assert_rule(root, :export_hygiene)
    end)
  end

  test "rejects future or stale context rows inside eligible_rows" do
    in_temp_project(fn root ->
      write_fixture_set!(
        root,
        eligible_rows: [
          %{
            "row_id" => "quote_future",
            "record_family" => "quote",
            "available_at_utc" => "2026-06-21T12:00:03Z",
            "source_event_time_utc" => "2026-06-21T12:00:03Z"
          },
          %{
            "row_id" => "quote_stale",
            "record_family" => "quote",
            "available_at_utc" => "2026-06-21T11:59:50Z",
            "source_event_time_utc" => "2026-06-21T11:59:50Z"
          }
        ]
      )

      findings =
        BoundaryGuardrails.findings(root)
        |> Enum.filter(&(&1.rule == :future_or_stale_eligible_row))

      assert length(findings) == 2
    end)
  end

  test "rejects eligible rows that are stale by source event age even when available_at_utc is fresh" do
    in_temp_project(fn root ->
      write_fixture_set!(
        root,
        eligible_rows: [
          %{
            "row_id" => "quote_stale_by_event_age",
            "record_family" => "quote",
            "available_at_utc" => "2026-06-21T12:00:02Z",
            "source_event_time_utc" => "2026-06-21T11:59:52Z"
          }
        ]
      )

      assert_rule(root, :future_or_stale_eligible_row)
    end)
  end

  test "rejects replay manifests with invalid timing fields" do
    in_temp_project(fn root ->
      write_fixture_set!(
        root,
        manifest: %{
          "decision_time" => "not-a-datetime",
          "market_context" => %{"staleness_threshold" => "five seconds"}
        }
      )

      assert_rule(root, :fixture_context_timing)
    end)
  end

  test "rejects replay manifests with malformed market_context" do
    in_temp_project(fn root ->
      write_fixture_set!(
        root,
        manifest: %{"market_context" => []}
      )

      assert_rule(root, :fixture_context_shape)
    end)
  end

  test "rejects replay manifests that omit eligible_rows" do
    in_temp_project(fn root ->
      write_fixture_set!(root)

      update_manifest!(root, fn manifest ->
        update_in(manifest, ["market_context"], &Map.delete(&1, "eligible_rows"))
      end)

      assert_rule(root, :eligible_rows_shape)
    end)
  end

  test "rejects eligible rows entries that are not objects" do
    in_temp_project(fn root ->
      write_fixture_set!(root, eligible_rows: ["not-a-row-object"])

      assert_rule(root, :eligible_rows_shape)
    end)
  end

  test "rejects future-only evidence outside audit_evidence" do
    in_temp_project(fn root ->
      write_fixture_set!(
        root,
        manifest: %{
          "market_context" => %{
            "nearest_quote_after" => %{
              "row_id" => "quote_120003",
              "available_at_utc" => "2026-06-21T12:00:03Z",
              "source_event_time_utc" => "2026-06-21T12:00:03Z"
            }
          }
        }
      )

      assert_rule(root, :audit_evidence_container)
    end)
  end

  test "rejects exported fixtures with direct locators, secret-like content, and execution language" do
    in_temp_project(fn root ->
      write_fixture_set!(
        root,
        envelope: %{
          "operational_signal_ref" => %{
            "alias" => "signal_fixture_001",
            "row_id" => 42,
            "durable_locator" => "tv_signals/42"
          },
          "signal_provenance_ref" => %{
            "kind" => "signal_provenance",
            "alias" => "signal_provenance_fixture_001",
            "row_id" => "sigprov-42"
          },
          "validation_failure_detail" => "raw_body retained for /Account/GetBalances before sending live order with api_key"
        }
      )

      assert_rule(root, :export_hygiene)
    end)
  end

  defp assert_rule(root, rule) do
    findings = BoundaryGuardrails.findings(root)

    assert Enum.any?(findings, &(&1.rule == rule)),
           "expected #{inspect(rule)} in #{inspect(findings)}"
  end

  defp assert_message(root, message_fragment) do
    findings = BoundaryGuardrails.findings(root)

    assert Enum.any?(findings, &String.contains?(&1.message, message_fragment)),
           "expected message containing #{inspect(message_fragment)} in #{inspect(findings)}"
  end

  defp in_temp_project(fun) do
    root =
      Path.join(
        System.tmp_dir!(),
        "boundary-guardrails-tradingview-fixture-test-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.rm_rf!(root)
    File.mkdir_p!(root)

    try do
      fun.(root)
    after
      File.rm_rf!(root)
    end
  end

  defp write_fixture_set!(root, overrides \\ []) do
    fixture_dir = Path.join(root, "docs/tradingview/fixtures")
    File.mkdir_p!(fixture_dir)

    File.write!(
      Path.join(root, "docs/tradingview/signal-envelope-checkpoint.md"),
      """
      tv.signal-envelope.v1
      signal_ref
      eligible_rows
      audit-only evidence
      """
    )

    envelope =
      deep_merge(
        %{
          "signal_schema_version" => "tv.signal-envelope.v1",
          "operational_signal_ref" => %{"alias" => "signal_fixture_001"},
          "payload_hash" => "sha256:example-redacted-payload",
          "canonical_instrument_id" => "BTC-CAD",
          "source_symbol" => "BTCCAD",
          "instrument_source" => "tradingview",
          "intended_side" => "buy",
          "source_event_time_utc" => "2026-06-21T12:00:00Z",
          "observed_at_utc" => "2026-06-21T12:00:02Z",
          "available_at_utc" => "2026-06-21T12:00:02Z",
          "validation_status" => "accepted",
          "validation_reason_code" => "accepted_replay",
          "validation_failure_detail" => nil,
          "signal_provenance_ref" => %{
            "kind" => "signal_provenance",
            "alias" => "signal_provenance_fixture_001"
          },
          "decision_provenance_ref" => %{
            "kind" => "decision_provenance",
            "alias" => "decision_provenance_fixture_001"
          }
        },
        Keyword.get(overrides, :envelope, %{})
      )

    manifest =
      %{
        "signal_schema_version" => "tv.signal-envelope.v1",
        "context_contract_version" => "tv.context-contract.v1",
        "fixture_category" => "accepted signal",
        "fixture_label" => "accepted_replay",
        "decision_time_basis" => "signal.available_at_utc",
        "available_at_rule" => "rows with available_at_utc <= decision_time only",
        "signal_ref" =>
          Keyword.get(overrides, :signal_ref, %{
            "fixture_alias" => "signal_fixture_001",
            "envelope_fixture" => "signal-envelope.valid.minimal.json"
          }),
        "signal_provenance_ref" => %{
          "kind" => "signal_provenance",
          "alias" => "signal_provenance_fixture_001"
        },
        "decision_provenance_ref" => %{
          "kind" => "decision_provenance",
          "alias" => "decision_provenance_fixture_001"
        },
        "decision_time" => "2026-06-21T12:00:02Z",
        "canonical_instrument_id" => "BTC-CAD",
        "market_context" => %{
          "source" => "ndax-public",
          "timezone" => "UTC",
          "session_calendar" => "24x7-crypto",
          "bar_orientation" => "end_anchored",
          "staleness_threshold" => "PT5S",
          "as_of_alignment" => %{
            "cutoff_available_at_utc" => "2026-06-21T12:00:02Z",
            "matched_quote_row_id" => "quote_120002"
          },
          "eligible_rows" =>
            Keyword.get(overrides, :eligible_rows, [
              %{
                "row_id" => "quote_120002",
                "record_family" => "quote",
                "available_at_utc" => "2026-06-21T12:00:02Z",
                "source_event_time_utc" => "2026-06-21T12:00:01Z"
              }
            ])
        },
        "row_counts" => %{
          "signals" => 1,
          "quotes" => 1,
          "bars" => 0
        }
      }
      |> deep_merge(Keyword.get(overrides, :manifest, %{}))

    write_json!(Path.join(fixture_dir, "signal-envelope.valid.minimal.json"), envelope)
    write_json!(Path.join(fixture_dir, "replay-input.accepted-replay.manifest.json"), manifest)
  end

  defp deep_merge(left, right) when is_map(left) and is_map(right) do
    Map.merge(left, right, fn _key, left_value, right_value -> deep_merge(left_value, right_value) end)
  end

  defp deep_merge(_left, right), do: right

  defp write_json!(path, data) do
    File.write!(path, Jason.encode_to_iodata!(data, pretty: true))
  end

  defp update_manifest!(root, fun) do
    path = Path.join(root, "docs/tradingview/fixtures/replay-input.accepted-replay.manifest.json")

    path
    |> File.read!()
    |> Jason.decode!()
    |> fun.()
    |> then(&write_json!(path, &1))
  end
end
