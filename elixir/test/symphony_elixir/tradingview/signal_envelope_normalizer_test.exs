defmodule SymphonyElixir.Tradingview.SignalEnvelopeNormalizerTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.Tradingview.SignalEnvelopeNormalizer

  @fixture_root Path.expand("../../fixtures/tradingview_signal_envelope_normalizer", __DIR__)

  test "normalizes an accepted fixture input deterministically" do
    input = fixture!("accepted_input.json")

    assert {:ok, normalized_one} = SignalEnvelopeNormalizer.normalize(input)
    assert {:ok, normalized_two} = SignalEnvelopeNormalizer.normalize(input)

    assert normalized_one == normalized_two
    assert Map.keys(normalized_one) |> Enum.sort() == accepted_keys()
    assert Map.get(normalized_one, :signal_schema_version) == "tv.signal-envelope.v1"
    assert Map.get(normalized_one, :validation_status) == "accepted"
    assert Map.get(normalized_one, :payload_hash) == accepted_payload_hash()
    assert Map.get(normalized_one, :signal_idempotency_hash) == accepted_idempotency_hash()
  end

  test "duplicate accepted fixtures share the same idempotency hash" do
    left = fixture!("accepted_input.json")
    right = fixture!("duplicate_input.json")

    assert {:ok, normalized_left} = SignalEnvelopeNormalizer.normalize(left)
    assert {:ok, normalized_right} = SignalEnvelopeNormalizer.normalize(right)

    assert Map.get(normalized_left, :signal_idempotency_hash) ==
             Map.get(normalized_right, :signal_idempotency_hash)

    assert Map.get(normalized_left, :payload_hash) ==
             Map.get(normalized_right, :payload_hash)
  end

  test "rejects invalid fixture input without retaining unsafe values" do
    input = fixture!("rejected_invalid_input.json")

    assert {:error, normalized} = SignalEnvelopeNormalizer.normalize(input)

    assert Map.keys(normalized) |> Enum.sort() == rejected_keys()
    assert Map.get(normalized, :validation_status) == "rejected"
    assert Map.get(normalized, :signal_provenance_ref) == nil
    assert Map.get(normalized, :decision_provenance_ref) == nil
    assert Map.get(normalized, :source_symbol) == nil
    assert Map.get(normalized, :intended_side) == nil
    assert Map.get(normalized, :payload_hash) == rejected_payload_hash()
    assert Map.get(normalized, :payload_size_bytes) == 38
  end

  test "rejects tainted accepted payload content" do
    input =
      fixture!("accepted_input.json")
      |> put_in(["payload_json", "message"], tainted_message())

    assert {:error, normalized} = SignalEnvelopeNormalizer.normalize(input)
    assert Map.get(normalized, :validation_status) == "rejected"
    assert Map.get(normalized, :validation_reason_code) == "invalid_payload"
  end

  test "rejects oversized payloads" do
    input =
      fixture!("accepted_input.json")
      |> put_in(["payload_json", "message"], String.duplicate("x", 5000))

    assert {:error, normalized} = SignalEnvelopeNormalizer.normalize(input)
    assert Map.get(normalized, :validation_status) == "rejected"
    assert Map.get(normalized, :validation_reason_code) == "invalid_payload"
  end

  test "rejects non-map input" do
    assert {:error, normalized} = SignalEnvelopeNormalizer.normalize("bad-input")
    assert Map.get(normalized, :validation_status) == "rejected"
    assert Map.get(normalized, :operational_signal_ref) == %{alias: nil}
  end

  test "marks legacy unmapped fixtures as non-deduplicable" do
    input = fixture!("legacy_unmapped_input.json")

    assert {:ok, normalized} = SignalEnvelopeNormalizer.normalize(input)
    assert Map.keys(normalized) |> Enum.sort() == legacy_keys()
    assert Map.get(normalized, :validation_status) == "legacy_unmapped"
    assert Map.get(normalized, :signal_idempotency_hash) == nil
    assert Map.get(normalized, :validation_reason_code) == "legacy_unmapped"
  end

  test "ignores post-decision context when normalizing accepted input" do
    base = fixture!("accepted_input.json")
    contaminated = fixture!("accepted_with_post_decision_context.json")

    assert {:ok, base_normalized} = SignalEnvelopeNormalizer.normalize(base)
    assert {:ok, contaminated_normalized} = SignalEnvelopeNormalizer.normalize(contaminated)

    assert base_normalized == contaminated_normalized
  end

  test "fails closed when provenance metadata is missing" do
    input = fixture!("missing_provenance_input.json")

    assert {:error, normalized} = SignalEnvelopeNormalizer.normalize(input)
    assert Map.get(normalized, :validation_status) == "rejected"
    assert Map.get(normalized, :validation_reason_code) == "invalid_payload"
    assert Map.get(normalized, :signal_provenance_ref) == nil
    assert Map.get(normalized, :decision_provenance_ref) == nil
  end

  test "rejects unexpected top-level input keys" do
    input =
      fixture!("accepted_input.json")
      |> Map.put("unexpected_marker", 1)

    assert {:error, normalized} = SignalEnvelopeNormalizer.normalize(input)
    assert Map.get(normalized, :validation_status) == "rejected"
  end

  test "rejects payload values that are not maps" do
    input =
      fixture!("accepted_input.json")
      |> Map.put("payload_json", "not-a-map")

    assert {:error, normalized} = SignalEnvelopeNormalizer.normalize(input)
    assert Map.get(normalized, :validation_status) == "rejected"
  end

  test "rejects payload maps with disallowed keys" do
    input =
      fixture!("accepted_input.json")
      |> put_in(["payload_json", "other"], "value")

    assert {:error, normalized} = SignalEnvelopeNormalizer.normalize(input)
    assert Map.get(normalized, :validation_status) == "rejected"
  end

  test "rejects nested tainted content" do
    input =
      fixture!("accepted_input.json")
      |> put_in(["payload_json", "message"], [%{"details" => tainted_message()}])

    assert {:error, normalized} = SignalEnvelopeNormalizer.normalize(input)
    assert Map.get(normalized, :validation_status) == "rejected"
  end

  test "accepts sell side with passthrough instrument ids" do
    input =
      fixture!("accepted_input.json")
      |> put_in(["payload_json", "side"], "sell")
      |> put_in(["payload_json", "symbol"], "BTCUSDTPERP")

    assert {:ok, normalized} = SignalEnvelopeNormalizer.normalize(input)
    assert Map.get(normalized, :intended_side) == "sell"
    assert Map.get(normalized, :canonical_instrument_id) == "BTCUSDTPERP"
  end

  test "accepts nil source event time when other accepted fields are present" do
    input =
      fixture!("accepted_input.json")
      |> put_in(["payload_json", "source_event_time_utc"], nil)

    assert {:ok, normalized} = SignalEnvelopeNormalizer.normalize(input)
    assert Map.get(normalized, :source_event_time_utc) == nil
  end

  test "rejects non-binary observed timestamps" do
    input =
      fixture!("accepted_input.json")
      |> Map.put("received_at_utc", 123)

    assert {:error, normalized} = SignalEnvelopeNormalizer.normalize(input)
    assert Map.get(normalized, :validation_status) == "rejected"
  end

  test "rejects invalid source event timestamps" do
    input =
      fixture!("accepted_input.json")
      |> put_in(["payload_json", "source_event_time_utc"], "not-a-timestamp")

    assert {:error, normalized} = SignalEnvelopeNormalizer.normalize(input)
    assert Map.get(normalized, :validation_status) == "rejected"
    assert Map.get(normalized, :source_event_time_utc) == nil
  end

  test "rejects non-binary source event timestamps" do
    input =
      fixture!("accepted_input.json")
      |> put_in(["payload_json", "source_event_time_utc"], 123)

    assert {:error, normalized} = SignalEnvelopeNormalizer.normalize(input)
    assert Map.get(normalized, :validation_status) == "rejected"
  end

  test "rejects invalid sides after accepted payload validation" do
    input =
      fixture!("accepted_input.json")
      |> put_in(["payload_json", "side"], "hold")

    assert {:error, normalized} = SignalEnvelopeNormalizer.normalize(input)
    assert Map.get(normalized, :validation_status) == "rejected"
  end

  test "keeps normalized output keys free of private account and trading terms" do
    input = fixture!("accepted_input.json")

    assert {:ok, normalized} = SignalEnvelopeNormalizer.normalize(input)

    keys =
      normalized
      |> Map.keys()
      |> Enum.map(&to_string/1)
      |> Enum.map(&String.downcase/1)

    refute Enum.any?(keys, &String.contains?(&1, "account"))
    refute Enum.any?(keys, &String.contains?(&1, "balance"))
    refute Enum.any?(keys, &String.contains?(&1, "position"))
    refute Enum.any?(keys, &String.contains?(&1, "order"))
    refute Enum.any?(keys, &String.contains?(&1, "execution"))
  end

  defp fixture!(name), do: read_json!(Path.join(@fixture_root, name))

  defp tainted_message do
    Enum.join([
      Enum.join(["api", "key"], "_"),
      "=",
      "runtime-only"
    ])
  end

  defp accepted_keys do
    [
      :available_at_utc,
      :canonical_instrument_id,
      :config_version_id,
      :decision_provenance_ref,
      :finalized_at_utc,
      :instrument_source,
      :intended_side,
      :observed_at_utc,
      :operational_signal_ref,
      :payload_hash,
      :signal_idempotency_hash,
      :signal_provenance_ref,
      :signal_schema_version,
      :source_event_time_utc,
      :source_symbol,
      :strategy_id,
      :strategy_version,
      :validation_failure_detail,
      :validation_reason_code,
      :validation_status
    ]
  end

  defp rejected_keys do
    accepted_keys()
    |> List.insert_at(11, :payload_size_bytes)
    |> Enum.sort()
  end

  defp legacy_keys, do: rejected_keys()

  defp accepted_payload_hash do
    "sha256:ab97edce496fe8e47e317e7f5e8d65149a89afd4c066e2f50b107a979ade6cfa"
  end

  defp accepted_idempotency_hash do
    "sha256:801661c3986cd1bcb28947ebcc18403c298ebac3c38375badaa71bc722031d4e"
  end

  defp rejected_payload_hash do
    "sha256:a6002a2cf624a965610f26e6158286e186c221ddf5f7827d3785ddf1745f390d"
  end

  defp read_json!(path) do
    path
    |> File.read!()
    |> Jason.decode!()
  end
end
