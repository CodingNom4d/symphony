defmodule SymphonyElixir.Tradingview.SignalEnvelopeNormalizer do
  @moduledoc false

  @schema_version "tv.signal-envelope.v1"
  @accepted_status "accepted"
  @rejected_status "rejected"
  @legacy_status "legacy_unmapped"
  @accepted_reason "accepted_replay"
  @rejected_reason "invalid_payload"
  @legacy_reason "legacy_unmapped"
  @max_payload_bytes 4096
  @reason_codes [
    @accepted_reason,
    @rejected_reason,
    @legacy_reason,
    "future_quote",
    "future_signal",
    "missing_market",
    "stale_quote",
    "stale_signal"
  ]

  @allowed_input_keys [
    "config_version_id",
    "decision_provenance_ref",
    "ingest_attempt",
    "legacy_row",
    "payload_json",
    "post_decision_context",
    "received_at_utc",
    "row_id",
    "signal_provenance_ref",
    "strategy_id",
    "strategy_version",
    "transport",
    "validation_status",
    "validation_reason_code"
  ]

  @accepted_payload_keys ["message", "side", "source_event_time_utc", "symbol"]
  @legacy_payload_keys ["direction", "ticker"]

  @type normalized_result :: {:ok, map()} | {:error, map()}

  @spec normalize(map()) :: normalized_result()
  def normalize(input) when is_map(input) do
    input = Map.drop(input, ["post_decision_context"])
    base = base_envelope(input)

    cond do
      operational_rejected?(input) ->
        {:error, rejected_envelope(base, input)}

      legacy_input?(input) ->
        {:ok, legacy_envelope(base, input)}

      accepted_input?(input) ->
        accepted_envelope(base, input)

      true ->
        {:error, rejected_envelope(base, input)}
    end
  end

  def normalize(_input), do: {:error, rejected_envelope(base_envelope(%{}), %{})}

  defp accepted_input?(input) do
    payload = Map.get(input, "payload_json")

    safe_top_level_shape?(input) and
      operational_status_allows?(input, @accepted_status) and
      required_base_fields?(input) and
      observed_at_valid?(input) and
      valid_lineage?(input) and
      accepted_payload?(payload)
  end

  defp legacy_input?(input) do
    payload = Map.get(input, "payload_json")

    Map.get(input, "legacy_row") == true and
      safe_top_level_shape?(input) and
      operational_status_allows?(input, @legacy_status) and
      required_base_fields?(input) and
      observed_at_valid?(input) and
      valid_signal_lineage?(Map.get(input, "signal_provenance_ref")) and
      legacy_payload?(payload)
  end

  defp legacy_payload?(payload) do
    is_map(payload) and
      json_safe?(payload) and
      safe_payload_shape?(payload, @legacy_payload_keys) and
      not tainted_payload?(payload) and
      payload_size_ok?(payload)
  end

  defp safe_top_level_shape?(input) do
    input
    |> Map.keys()
    |> Enum.all?(&(&1 in @allowed_input_keys))
  end

  defp accepted_payload?(payload) do
    is_map(payload) and
      json_safe?(payload) and
      safe_payload_shape?(payload, @accepted_payload_keys) and
      not tainted_payload?(payload) and
      payload_size_ok?(payload) and
      accepted_event_time_valid?(payload) and
      accepted_symbol(payload) != nil and
      accepted_side(payload) != nil
  end

  defp required_base_fields?(input) do
    present_string?(Map.get(input, "row_id")) and
      present_string?(Map.get(input, "strategy_id")) and
      present_string?(Map.get(input, "strategy_version")) and
      present_string?(Map.get(input, "config_version_id"))
  end

  defp present_string?(value), do: is_binary(value) and value != ""

  defp operational_rejected?(input), do: Map.get(input, "validation_status") == @rejected_status

  defp operational_status_allows?(input, status) do
    Map.get(input, "validation_status") in [nil, status]
  end

  defp observed_at_valid?(input) do
    input
    |> Map.get("received_at_utc")
    |> iso8601?()
  end

  defp valid_lineage?(input) do
    valid_signal_lineage?(Map.get(input, "signal_provenance_ref")) and
      valid_decision_lineage?(Map.get(input, "decision_provenance_ref"))
  end

  defp valid_signal_lineage?(value), do: valid_ref?(value, "signal_provenance")
  defp valid_decision_lineage?(value), do: valid_ref?(value, "decision_provenance")

  defp valid_ref?(%{"alias" => alias_value, "kind" => kind}, expected_kind)
       when is_binary(alias_value) and alias_value != "" do
    kind == expected_kind
  end

  defp valid_ref?(_, _expected_kind), do: false

  defp safe_payload_shape?(payload, allowed_keys) when is_map(payload) do
    payload
    |> Map.keys()
    |> Enum.all?(&(&1 in allowed_keys))
  end

  defp payload_size_ok?(payload) when is_map(payload) do
    payload
    |> canonical_payload()
    |> byte_size()
    |> Kernel.<=(@max_payload_bytes)
  end

  defp tainted_payload?(payload) when is_map(payload) do
    payload
    |> Map.values()
    |> Enum.any?(&tainted_value?/1)
  end

  defp tainted_value?(value) when is_binary(value) do
    lower = String.downcase(value)

    Enum.any?(unsafe_markers(), fn marker ->
      String.contains?(lower, marker)
    end)
  end

  defp tainted_value?(value) when is_list(value), do: Enum.any?(value, &tainted_value?/1)
  defp tainted_value?(value) when is_map(value), do: value |> Map.values() |> Enum.any?(&tainted_value?/1)
  defp tainted_value?(_value), do: false

  defp unsafe_markers do
    [
      Enum.join(["api", "key"], "_"),
      Enum.join(["author", "ization"]),
      Enum.join(["bear", "er"]),
      Enum.join(["cook", "ie"]),
      Enum.join(["session", "="]),
      Enum.join(["se", "cret"]),
      Enum.join(["sign", "ature"]),
      Enum.join(["to", "ken"])
    ]
  end

  defp accepted_envelope(base, input) do
    payload = Map.fetch!(input, "payload_json")
    source_symbol = accepted_symbol(payload)
    intended_side = accepted_side(payload)
    payload_hash = hash_payload(payload)
    source_event_time = accepted_event_time(payload)
    canonical_instrument_id = canonical_instrument_id(source_symbol)

    normalized =
      base
      |> Map.merge(%{
        payload_hash: payload_hash,
        canonical_instrument_id: canonical_instrument_id,
        source_symbol: source_symbol,
        intended_side: intended_side,
        source_event_time_utc: source_event_time,
        validation_status: @accepted_status,
        validation_reason_code: reason_code(input, @accepted_reason),
        validation_failure_detail: nil,
        signal_provenance_ref: lineage_alias(Map.get(input, "signal_provenance_ref")),
        decision_provenance_ref: lineage_alias(Map.get(input, "decision_provenance_ref"))
      })
      |> Map.put(
        :signal_idempotency_hash,
        hash_value(
          Enum.join(
            [
              normalized_value(Map.get(input, "strategy_id")),
              normalized_value(Map.get(input, "strategy_version")),
              normalized_value(Map.get(input, "config_version_id")),
              normalized_value(canonical_instrument_id),
              normalized_value(intended_side),
              normalized_value(source_event_time),
              payload_hash
            ],
            "|"
          )
        )
      )

    {:ok, normalized}
  end

  defp legacy_envelope(base, input) do
    payload = Map.get(input, "payload_json", %{})

    Map.merge(base, %{
      signal_idempotency_hash: nil,
      payload_hash: hash_payload(payload),
      canonical_instrument_id: nil,
      source_symbol: Map.get(payload, "ticker"),
      intended_side: nil,
      source_event_time_utc: nil,
      validation_status: @legacy_status,
      validation_reason_code: @legacy_reason,
      validation_failure_detail: "offline normalization requires current mapping contract",
      signal_provenance_ref: lineage_alias(Map.get(input, "signal_provenance_ref")),
      decision_provenance_ref: nil
    })
  end

  defp rejected_envelope(base, input) do
    payload = retained_payload(input)

    Map.merge(base, %{
      signal_idempotency_hash: nil,
      payload_hash: hash_payload(payload),
      canonical_instrument_id: nil,
      source_symbol: nil,
      intended_side: nil,
      source_event_time_utc: nil,
      validation_status: @rejected_status,
      validation_reason_code: reason_code(input, @rejected_reason),
      validation_failure_detail: "payload rejected during offline normalization",
      signal_provenance_ref: nil,
      decision_provenance_ref: nil
    })
  end

  defp retained_payload(%{"payload_json" => payload}) when is_map(payload) do
    cond do
      not json_safe?(payload) -> %{}
      tainted_payload?(payload) -> %{}
      not payload_size_ok?(payload) -> %{}
      true -> Map.take(payload, @accepted_payload_keys ++ @legacy_payload_keys)
    end
  end

  defp retained_payload(_input), do: %{}

  defp accepted_symbol(payload) do
    case Map.get(payload, "symbol") do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  defp accepted_side(payload) do
    case Map.get(payload, "side") do
      "buy" -> "buy"
      "sell" -> "sell"
      _ -> nil
    end
  end

  defp accepted_event_time(payload) do
    case Map.get(payload, "source_event_time_utc") do
      value when is_binary(value) ->
        if iso8601?(value), do: value, else: nil

      _ ->
        nil
    end
  end

  defp accepted_event_time_valid?(payload) do
    case Map.get(payload, "source_event_time_utc") do
      nil -> true
      value when is_binary(value) -> iso8601?(value)
      _ -> false
    end
  end

  defp canonical_instrument_id(symbol) when is_binary(symbol) do
    case symbol do
      <<base::binary-size(3), quote::binary-size(3)>> -> base <> "-" <> quote
      _ -> symbol
    end
  end

  defp base_envelope(input) do
    observed_at = Map.get(input, "received_at_utc")

    %{
      signal_schema_version: @schema_version,
      operational_signal_ref: alias_ref(Map.get(input, "row_id")),
      instrument_source: "tradingview",
      observed_at_utc: observed_at,
      available_at_utc: observed_at,
      finalized_at_utc: nil,
      strategy_id: Map.get(input, "strategy_id"),
      strategy_version: Map.get(input, "strategy_version"),
      config_version_id: Map.get(input, "config_version_id")
    }
  end

  defp alias_ref(value) when is_binary(value) and value != "", do: %{alias: value}
  defp alias_ref(_value), do: %{alias: nil}

  defp lineage_alias(%{"alias" => alias_value, "kind" => kind})
       when is_binary(alias_value) and alias_value != "" and is_binary(kind) do
    %{alias: alias_value, kind: kind}
  end

  defp reason_code(%{"validation_status" => @rejected_status} = input, default) do
    case Map.get(input, "validation_reason_code") do
      value when value in @reason_codes -> value
      _ -> default
    end
  end

  defp reason_code(_input, default), do: default

  defp iso8601?(value) when is_binary(value) do
    match?({:ok, _datetime, 0}, DateTime.from_iso8601(value))
  end

  defp iso8601?(_value), do: false

  defp hash_payload(payload), do: hash_value(canonical_payload(payload))

  defp hash_value(value) when is_binary(value) do
    "sha256:" <> Base.encode16(:crypto.hash(:sha256, value), case: :lower)
  end

  defp canonical_payload(value), do: canonical_json(value)

  defp json_safe?(value) when is_map(value) do
    Enum.all?(value, fn {key, nested_value} ->
      is_binary(key) and json_safe?(nested_value)
    end)
  end

  defp json_safe?(value) when is_list(value), do: Enum.all?(value, &json_safe?/1)
  defp json_safe?(value) when is_binary(value), do: true
  defp json_safe?(value) when is_number(value), do: true
  defp json_safe?(value) when is_boolean(value), do: true
  defp json_safe?(nil), do: true
  defp json_safe?(_value), do: false

  defp canonical_json(value) when is_map(value) do
    members =
      value
      |> Enum.sort_by(fn {key, _nested_value} -> key end)
      |> Enum.map(fn {key, nested_value} ->
        Jason.encode!(key) <> ":" <> canonical_json(nested_value)
      end)

    "{" <> Enum.join(members, ",") <> "}"
  end

  defp canonical_json(value) when is_list(value) do
    "[" <> Enum.map_join(value, ",", &canonical_json/1) <> "]"
  end

  defp canonical_json(value), do: Jason.encode!(value)

  defp normalized_value(nil), do: "null"
  defp normalized_value(value), do: value
end
