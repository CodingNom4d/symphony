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

  test "prefers the nearest future row and least-stale prior row regardless of input order" do
    signal_envelope = docs_fixture!("signal-envelope.valid.missing-market-context.json")

    context_rows = [
      %{
        "row_id" => "quote_120030",
        "record_family" => "quote",
        "available_at_utc" => "2026-06-21T12:00:30Z",
        "source_event_time_utc" => "2026-06-21T12:00:30Z"
      },
      %{
        "row_id" => "quote_120021",
        "record_family" => "quote",
        "available_at_utc" => "2026-06-21T12:00:21Z",
        "source_event_time_utc" => "2026-06-21T12:00:21Z"
      },
      %{
        "row_id" => "bar_115940_1m",
        "record_family" => "bar",
        "available_at_utc" => "2026-06-21T11:59:40Z",
        "source_event_time_utc" => "2026-06-21T11:59:40Z"
      },
      %{
        "row_id" => "bar_120000_1m",
        "record_family" => "bar",
        "available_at_utc" => "2026-06-21T12:00:00Z",
        "source_event_time_utc" => "2026-06-21T12:00:00Z"
      }
    ]

    manifest = ReplayManifestAssembler.assemble(signal_envelope, context_rows)

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

    assert get_in(manifest, ["row_counts"]) == %{
             "signals" => 1,
             "quotes" => 2,
             "bars" => 2
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
