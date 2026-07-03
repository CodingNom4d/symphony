defmodule SymphonyElixir.Tradingview.ReplayManifestAssembler do
  @moduledoc false

  @context_contract_version "tv.context-contract.v1"
  @decision_time_basis "signal.available_at_utc"
  @available_at_rule "rows with available_at_utc <= decision_time only"
  @accepted_fixture_label "accepted_replay"
  @insufficient_fixture_label "insufficient_data"
  @staleness_threshold "PT5S"
  @staleness_milliseconds 5_000
  @signal_envelope_fixtures_by_alias %{
    "signal_fixture_001" => "signal-envelope.valid.minimal.json",
    "signal_fixture_005" => "signal-envelope.valid.missing-market-context.json"
  }

  @type manifest :: map()

  @spec assemble(map(), [map()]) :: manifest()
  def assemble(signal_envelope, market_context_rows) do
    decision_time =
      signal_envelope
      |> fetch_value!(:available_at_utc)
      |> parse_datetime!()

    {eligible_rows, audit_evidence, row_counts} =
      summarize_context_rows(List.wrap(market_context_rows), decision_time)

    {matched_quote_row_id, matched_bar_row_id} = matched_row_ids(eligible_rows)
    fixture_label = fixture_label(matched_quote_row_id, matched_bar_row_id)

    %{
      "signal_schema_version" => fetch_value!(signal_envelope, :signal_schema_version),
      "context_contract_version" => @context_contract_version,
      "fixture_category" => fixture_category(fixture_label),
      "fixture_label" => fixture_label,
      "decision_time_basis" => @decision_time_basis,
      "available_at_rule" => @available_at_rule,
      "signal_ref" => signal_ref(signal_envelope),
      "signal_provenance_ref" => fetch_value!(signal_envelope, :signal_provenance_ref),
      "decision_provenance_ref" => fetch_value!(signal_envelope, :decision_provenance_ref),
      "decision_time" => DateTime.to_iso8601(decision_time),
      "canonical_instrument_id" => fetch_value!(signal_envelope, :canonical_instrument_id),
      "market_context" =>
        market_context(
          eligible_rows,
          audit_evidence,
          decision_time,
          matched_quote_row_id,
          matched_bar_row_id
        ),
      "row_counts" => row_counts
    }
    |> maybe_add_insufficient_reason(fixture_label)
  end

  defp summarize_context_rows(rows, decision_time) do
    Enum.reduce(rows, {[], %{}, %{"signals" => 1, "quotes" => 0, "bars" => 0}}, fn row,
                                                                                   {
                                                                                     eligible_rows,
                                                                                     audit_evidence,
                                                                                     row_counts
                                                                                   } ->
      record_family = fetch_value!(row, :record_family)
      available_at = row |> fetch_value!(:available_at_utc) |> parse_datetime!()
      source_event_time = row |> fetch_value!(:source_event_time_utc) |> parse_datetime!()
      row_counts = increment_row_counts(row_counts, record_family)

      cond do
        DateTime.compare(available_at, decision_time) == :gt ->
          future_row = copy_row_fields(row)
          audit_key = "nearest_#{record_family}_after"

          {
            eligible_rows,
            Map.put_new(audit_evidence, audit_key, future_row),
            row_counts
          }

        DateTime.diff(decision_time, source_event_time, :millisecond) > @staleness_milliseconds ->
          stale_row =
            row
            |> copy_row_fields()
            |> Map.put("age_at_decision_ms", DateTime.diff(decision_time, source_event_time, :millisecond))

          audit_key = "stale_#{record_family}_before"

          {
            eligible_rows,
            Map.put_new(audit_evidence, audit_key, stale_row),
            row_counts
          }

        true ->
          {[copy_row_fields(row) | eligible_rows], audit_evidence, row_counts}
      end
    end)
    |> then(fn {eligible_rows, audit_evidence, row_counts} ->
      {Enum.reverse(eligible_rows), audit_evidence, row_counts}
    end)
  end

  defp matched_row_ids(eligible_rows) do
    {
      family_row_id(eligible_rows, "quote"),
      family_row_id(eligible_rows, "bar")
    }
  end

  defp family_row_id(eligible_rows, family) do
    eligible_rows
    |> Enum.find_value(fn row ->
      if Map.get(row, "record_family") == family, do: Map.get(row, "row_id")
    end)
  end

  defp market_context(
         eligible_rows,
         audit_evidence,
         decision_time,
         matched_quote_row_id,
         matched_bar_row_id
       ) do
    %{
      "source" => "ndax-public",
      "timezone" => "UTC",
      "session_calendar" => "24x7-crypto",
      "bar_orientation" => "end_anchored",
      "staleness_threshold" => @staleness_threshold,
      "as_of_alignment" => %{
        "cutoff_available_at_utc" => DateTime.to_iso8601(decision_time),
        "matched_quote_row_id" => matched_quote_row_id,
        "matched_bar_row_id" => matched_bar_row_id
      },
      "eligible_rows" => eligible_rows
    }
    |> maybe_add_audit_evidence(audit_evidence)
  end

  defp maybe_add_audit_evidence(market_context, audit_evidence) when map_size(audit_evidence) == 0,
    do: market_context

  defp maybe_add_audit_evidence(market_context, audit_evidence),
    do: Map.put(market_context, "audit_evidence", audit_evidence)

  defp maybe_add_insufficient_reason(manifest, @accepted_fixture_label), do: manifest

  defp maybe_add_insufficient_reason(manifest, @insufficient_fixture_label) do
    manifest
    |> Map.put("canonical_reason_code", "missing_market")
    |> Map.put("decision_time_offset", "PT0S")
  end

  defp fixture_label(matched_quote_row_id, matched_bar_row_id) do
    if matched_quote_row_id != nil and matched_bar_row_id != nil do
      @accepted_fixture_label
    else
      @insufficient_fixture_label
    end
  end

  defp fixture_category(@accepted_fixture_label), do: "accepted signal"
  defp fixture_category(@insufficient_fixture_label), do: "insufficient context"

  defp increment_row_counts(row_counts, "quote"),
    do: Map.update!(row_counts, "quotes", &(&1 + 1))

  defp increment_row_counts(row_counts, "bar"),
    do: Map.update!(row_counts, "bars", &(&1 + 1))

  defp signal_ref(signal_envelope) do
    fixture_alias =
      signal_envelope
      |> fetch_value!(:operational_signal_ref)
      |> fetch_value!(:alias)

    %{
      "fixture_alias" => fixture_alias,
      "envelope_fixture" => Map.fetch!(@signal_envelope_fixtures_by_alias, fixture_alias)
    }
  end

  defp copy_row_fields(row) do
    %{
      "row_id" => fetch_value!(row, :row_id),
      "record_family" => fetch_value!(row, :record_family),
      "available_at_utc" => fetch_value!(row, :available_at_utc),
      "source_event_time_utc" => fetch_value!(row, :source_event_time_utc)
    }
  end

  defp fetch_value!(map, key) when is_map(map) do
    Map.get(map, key) || Map.fetch!(map, Atom.to_string(key))
  end

  defp parse_datetime!(value) do
    {:ok, datetime, 0} = DateTime.from_iso8601(value)
    datetime
  end
end
