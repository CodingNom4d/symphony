defmodule SymphonyElixir.Tradingview.ReplayManifestAssemblerTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Tradingview.ReplayManifestAssembler

  @fixture_root Path.expand("../../fixtures/tradingview_replay_manifest_assembler", __DIR__)
  @docs_fixture_root Path.expand("../../../../docs/tradingview/fixtures", __DIR__)

  test "assembles the accepted replay fixture path from a normalized signal envelope" do
    signal_envelope = docs_fixture!("signal-envelope.valid.minimal.json")
    context_rows = fixture!("accepted_context_rows.json")
    expected = docs_fixture!("replay-input.accepted-replay.manifest.json")

    manifest = ReplayManifestAssembler.assemble(signal_envelope, context_rows)

    assert manifest == expected

    assert get_in(manifest, ["signal_ref"]) == %{
             "fixture_alias" => "signal_fixture_001",
             "envelope_fixture" => "signal-envelope.valid.minimal.json"
           }
  end

  test "assembles the insufficient-context fixture path while keeping future and stale rows audit-only" do
    signal_envelope = docs_fixture!("signal-envelope.valid.missing-market-context.json")
    context_rows = fixture!("insufficient_context_rows.json")
    expected = docs_fixture!("replay-input.insufficient-data.missing_market.manifest.json")

    manifest = ReplayManifestAssembler.assemble(signal_envelope, context_rows)

    assert manifest == expected

    assert get_in(manifest, ["signal_ref"]) == %{
             "fixture_alias" => "signal_fixture_005",
             "envelope_fixture" => "signal-envelope.valid.missing-market-context.json"
           }

    assert get_in(manifest, ["fixture_label"]) == "insufficient_data"
    assert get_in(manifest, ["canonical_reason_code"]) == "missing_market"
    assert get_in(manifest, ["market_context", "eligible_rows"]) == []

    assert get_in(manifest, ["market_context", "audit_evidence"]) == %{
             "nearest_quote_after" => %{
               "row_id" => "quote_120021",
               "record_family" => "quote",
               "available_at_utc" => "2026-06-21T12:00:21Z",
               "source_event_time_utc" => "2026-06-21T12:00:21Z"
             },
             "stale_bar_before" => %{
               "row_id" => "bar_120000_1m",
               "record_family" => "bar",
               "available_at_utc" => "2026-06-21T12:00:00Z",
               "source_event_time_utc" => "2026-06-21T12:00:00Z",
               "age_at_decision_ms" => 20_000
             }
           }
  end

  test "treats subsecond rows older than the staleness threshold as stale" do
    signal_envelope = docs_fixture!("signal-envelope.valid.minimal.json")

    context_rows = [
      %{
        "row_id" => "quote_115956_999",
        "record_family" => "quote",
        "available_at_utc" => "2026-06-21T11:59:56.999Z",
        "source_event_time_utc" => "2026-06-21T11:59:56.999Z"
      },
      %{
        "row_id" => "bar_120000_1m",
        "record_family" => "bar",
        "available_at_utc" => "2026-06-21T12:00:00Z",
        "source_event_time_utc" => "2026-06-21T12:00:00Z"
      }
    ]

    manifest = ReplayManifestAssembler.assemble(signal_envelope, context_rows)

    assert get_in(manifest, ["fixture_label"]) == "insufficient_data"
    refute Enum.any?(get_in(manifest, ["market_context", "eligible_rows"]), &(&1["row_id"] == "quote_115956_999"))

    assert get_in(manifest, ["market_context", "audit_evidence", "stale_quote_before"]) == %{
             "row_id" => "quote_115956_999",
             "record_family" => "quote",
             "available_at_utc" => "2026-06-21T11:59:56.999Z",
             "source_event_time_utc" => "2026-06-21T11:59:56.999Z",
             "age_at_decision_ms" => 5_001
           }
  end

  test "assembles the future quote rejected fixture path" do
    signal_envelope = docs_fixture!("signal-envelope.valid.future-quote-context.json")
    expected = docs_fixture!("replay-input.future-data-rejected.future_quote.manifest.json")

    context_rows = [
      %{
        "row_id" => "quote_120003",
        "record_family" => "quote",
        "available_at_utc" => "2026-06-21T12:00:03Z",
        "source_event_time_utc" => "2026-06-21T12:00:03Z"
      }
    ]

    manifest = ReplayManifestAssembler.assemble(signal_envelope, context_rows)

    assert manifest == expected
  end

  test "assembles the stale quote rejected fixture path" do
    signal_envelope = docs_fixture!("signal-envelope.valid.stale-context.json")
    expected = docs_fixture!("replay-input.stale-context.stale_quote.manifest.json")

    context_rows = [
      %{
        "row_id" => "quote_120001",
        "record_family" => "quote",
        "available_at_utc" => "2026-06-21T12:00:01Z",
        "source_event_time_utc" => "2026-06-21T12:00:01Z"
      }
    ]

    manifest = ReplayManifestAssembler.assemble(signal_envelope, context_rows)

    assert manifest == expected
  end

  test "uses an explicit envelope fixture name for new signal aliases" do
    signal_envelope =
      "signal-envelope.valid.future-quote-context.json"
      |> docs_fixture!()
      |> Map.put("envelope_fixture", "signal-envelope.valid.future-quote-context.json")

    context_rows = fixture!("accepted_context_rows.json")

    manifest = ReplayManifestAssembler.assemble(signal_envelope, context_rows)

    assert get_in(manifest, ["signal_ref"]) == %{
             "fixture_alias" => "signal_fixture_003",
             "envelope_fixture" => "signal-envelope.valid.future-quote-context.json"
           }
  end

  defp docs_fixture!(name), do: read_json!(Path.join(@docs_fixture_root, name))
  defp fixture!(name), do: read_json!(Path.join(@fixture_root, name))

  defp read_json!(path) do
    path
    |> File.read!()
    |> Jason.decode!()
  end
end
