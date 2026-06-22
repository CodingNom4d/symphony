defmodule SymphonyElixir.NdaxPublicCapabilityGateTest do
  use ExUnit.Case, async: true

  @elixir_root Path.expand("../..", __DIR__)
  @repo_root Path.expand("..", @elixir_root)
  @fixture_root Path.expand("../fixtures/ndax_public_capability_gate", __DIR__)
  @manifest_path Path.join(@repo_root, "docs/ndax_public_capability_gate.allowlist.json")

  test "manifest is deny-by-default and references existing fixtures" do
    manifest = read_json!(@manifest_path)

    assert manifest["default_policy"] == "deny"

    assert manifest["transport_allowlist"] == [
             %{
               "scheme" => "wss",
               "host" => "api.ndax.io",
               "path" => "/WSGateway/",
               "purpose" => "public NDAX market-data websocket gateway",
               "evidence" => "live public probes on 2026-06-21"
             }
           ]

    allowlisted_methods =
      Enum.map(manifest["method_allowlist"], & &1["name"])

    assert allowlisted_methods == [
             "GetInstruments",
             "GetInstrument",
             "GetLevel1",
             "GetL2Snapshot",
             "SubscribeLevel1",
             "SubscribeLevel2",
             "SubscribeTicker",
             "SubscribeTrades"
           ]

    Enum.each(manifest["method_allowlist"], fn entry ->
      assert File.exists?(Path.expand(entry["fixture"], @repo_root))
    end)

    Enum.each(manifest["excluded_evidence"], fn entry ->
      assert File.exists?(Path.expand(entry["fixture"], @repo_root))
    end)
  end

  test "positive fixtures preserve the exact field contracts later issues may consume" do
    instrument_list = fixture!("get_instruments.sample.json")
    assert is_list(instrument_list)
    assert [_ | _] = instrument_list

    assert Enum.all?(
             ~w(OMSId InstrumentId Symbol Product1Symbol Product2Symbol SessionStatus QuantityIncrement PriceIncrement MinimumQuantity MinimumPrice IsDisable),
             &Map.has_key?(hd(instrument_list), &1)
           )

    instrument = fixture!("get_instrument.sample.json")
    assert instrument["OMSId"] == 1
    assert instrument["InstrumentId"] == 1
    assert instrument["Symbol"] == "BTCCAD"

    level1 = fixture!("get_level1.sample.json")
    assert Enum.all?(~w(OMSId InstrumentId BestBid BestOffer LastTradedPx LastTradedQty LastTradeTime TimeStamp BidQty AskQty), &Map.has_key?(level1, &1))
    assert millisecond_timestamp?(level1["LastTradeTime"])
    assert millisecond_timestamp?(level1["TimeStamp"])

    l2_snapshot = fixture!("get_l2_snapshot_depth20.sample.json")
    assert l2_snapshot["depth_requested"] == 20
    assert length(l2_snapshot["rows"]) == 40
    assert Enum.all?(l2_snapshot["rows"], &(is_list(&1) and length(&1) == 10))
    assert Enum.all?(l2_snapshot["rows"], &(Enum.at(&1, 7) == 1))

    level1_update = fixture!("subscribe_level1_update_event.sample.json")
    assert Enum.all?(~w(OMSId InstrumentId BestBid BestOffer LastTradedPx LastTradeTime TimeStamp BidQty AskQty), &Map.has_key?(level1_update, &1))
    assert millisecond_timestamp?(level1_update["LastTradeTime"])
    assert millisecond_timestamp?(level1_update["TimeStamp"])

    level2_update = fixture!("subscribe_level2_update_event.sample.json")
    assert [_ | _] = level2_update["rows"]
    assert Enum.all?(level2_update["rows"], &(is_list(&1) and length(&1) == 10))
    assert Enum.all?(level2_update["rows"], &(Enum.at(&1, 7) == 1))

    ticker = fixture!("subscribe_ticker_interval60.sample.json")
    assert ticker["interval"] == 60
    assert ticker["include_last_count"] == 5
    assert length(ticker["bars"]) == 5
    assert Enum.all?(ticker["bars"], &(is_list(&1) and length(&1) == 10))

    [first_bar, second_bar | _] = ticker["bars"]
    assert Enum.at(second_bar, 0) - Enum.at(first_bar, 0) == 60_000
    assert Enum.at(second_bar, 9) - Enum.at(first_bar, 9) == 60_000

    trades = fixture!("subscribe_trades.sample.json")
    assert trades["include_last_count"] == 5
    assert length(trades["rows"]) == 5
    assert Enum.all?(trades["rows"], &(is_list(&1) and length(&1) == 11))
    assert Enum.all?(trades["rows"], &millisecond_timestamp?(Enum.at(&1, 6)))
  end

  test "negative evidence keeps ambiguous or rejected surfaces out of the allowlist" do
    ticker_history = fixture!("get_ticker_history.empty_payload.sample.json")
    assert ticker_history["payload"] == ""

    trades_history = fixture!("get_trades_history.endpoint_not_found.sample.json")
    assert trades_history["message_type"] == 5
    assert trades_history["payload"] == "Endpoint Not Found"

    ticker_interval_error = fixture!("subscribe_ticker_interval1_error.sample.json")
    assert ticker_interval_error["result"] == false
    assert ticker_interval_error["errorcode"] == 100
    assert String.contains?(ticker_interval_error["errormsg"], "Unsupported Ticker Interval")
    assert String.contains?(ticker_interval_error["errormsg"], "[60,300,900")
  end

  test "capture decision matches the evidence boundary" do
    manifest = read_json!(@manifest_path)
    decision = manifest["capture_decision"]

    assert decision["status"] == "feasible"
    assert String.contains?(decision["decision"], "websocket")
    assert String.contains?(decision["decision"], "REST")
    assert Enum.any?(decision["reason"], &String.contains?(&1, "50 requests per minute"))
    assert Enum.any?(decision["reason"], &String.contains?(&1, "SubscribeTicker does not support Interval 1"))
  end

  test "gate preserves the existing public REST order-book collector as legacy dry-run scope" do
    manifest = read_json!(@manifest_path)
    forbidden_policy = manifest["forbidden_policy"]

    assert Enum.any?(
             forbidden_policy,
             &String.contains?(&1, "existing tested public REST /order-book dry-run collector")
           )

    assert Enum.any?(
             forbidden_policy,
             &String.contains?(&1, "new NDAX REST paths are forbidden for 1-second capture")
           )

    refute Enum.member?(
             forbidden_policy,
             "All NDAX REST paths are forbidden until a later human-approved issue proves exact public paths and fields."
           )
  end

  defp fixture!(name), do: read_json!(Path.join(@fixture_root, name))

  defp read_json!(path) do
    path
    |> File.read!()
    |> Jason.decode!()
  end

  defp millisecond_timestamp?(value) when is_integer(value), do: value > 1_000_000_000_000
  defp millisecond_timestamp?(value) when is_float(value), do: value > 1.0e12
  defp millisecond_timestamp?(_value), do: false
end
