# NDAX Public Capability Gate

Captured on 2026-06-21 for COD-25.

This gate is intentionally narrow. It governs future NDAX public websocket capture work, especially the 1-second capture path, and allows only the public websocket gateway plus the exact method/request shapes listed in [docs/ndax_public_capability_gate.allowlist.json](./ndax_public_capability_gate.allowlist.json). Every other NDAX path is forbidden for that new capture surface unless a later human-approved issue expands the allowlist.

This gate does not revoke the repository's existing tested public REST `/order-book` dry-run collector. That collector remains a legacy/current public-data surface for the dry-run stack until a later human-approved issue replaces or quarantines it. New 1-second capture, replay, and backtesting work must not expand REST usage through this gate.

## Sources

- Official NDAX API support guide: `https://ndax.io/en/support/api_access_and_developer_tools/api-comprehensive-guide`
- Official NDAX API reference: `https://apidoc.ndax.io/`
- NDAX-maintained websocket protocol reference: `https://github.com/NDAXlO/ndax-api-documentation`

## Allowlisted Surface

Transport:

- `wss://api.ndax.io/WSGateway/`

Methods:

- `GetInstruments` with `{"OMSId":1}`
- `GetInstrument` with `{"OMSId":1,"InstrumentId":1}`
- `GetLevel1` with `{"OMSId":1,"InstrumentId":1}`
- `GetL2Snapshot` with `{"OMSId":1,"InstrumentId":1,"Depth":20}`
- `SubscribeLevel1` with `{"OMSId":1,"InstrumentId":1}`
- `SubscribeLevel2` with `{"OMSId":1,"InstrumentId":1,"Depth":20}`
- `SubscribeTicker` with `{"OMSId":1,"InstrumentId":1,"Interval":60,"IncludeLastCount":5}`
- `SubscribeTrades` with `{"OMSId":1,"InstrumentId":1,"IncludeLastCount":5}`

Committed fixture evidence for those exact payload shapes lives under [elixir/test/fixtures/ndax_public_capability_gate](../elixir/test/fixtures/ndax_public_capability_gate).

## Forbidden Surface

These are forbidden now:

- Any new NDAX capture transport other than `wss://api.ndax.io/WSGateway/`
- Any new NDAX REST path for 1-second capture, replay, or backtesting
- Any private, authenticated, account, trading, funding, ticket, treasury, or reporting method
- `GetTickerHistory`
- `GetTradesHistory`
- `SubscribeTicker` with `Interval: 1`
- `GetL2Snapshot` or `SubscribeLevel2` at depths other than `20`
- Any method, parameter shape, or path not named in the allowlist manifest
- Any unknown or newly discovered NDAX endpoint

## Live Probe Findings

- `GetInstruments`, `GetInstrument`, `GetLevel1`, and `GetL2Snapshot` all returned public unauthenticated responses on the websocket gateway.
- `GetL2Snapshot` with `Depth:20` returned 40 rows, which is the expected top-20 bid plus top-20 ask shape.
- `SubscribeLevel1` returned a snapshot and later a `Level1UpdateEvent`.
- `SubscribeLevel2` returned a snapshot and repeated `Level2UpdateEvent` frames. A bounded public probe observed many updates inside five seconds.
- `SubscribeTicker` worked at `Interval:60` with `IncludeLastCount:5` and returned five bar rows. `Interval:1` was rejected with an unsupported-interval error.
- `SubscribeTrades` returned public trade rows suitable for tape-style downstream field mapping.
- `GetTickerHistory` returned an empty payload in live unauthenticated probes, so it is not safe to consume.
- `GetTradesHistory` returned `Endpoint Not Found` in live unauthenticated probes, so it remains outside the allowlist.

## Timestamp And Row Contracts

The committed fixtures prove the exact field shapes later issues may rely on:

- Level 1 snapshots and updates use named fields with millisecond timestamps in `LastTradeTime` and `TimeStamp`.
- Level 2 snapshot and update payloads are positional arrays of length 10.
- Ticker rows are positional arrays of length 10.
- Trade rows are positional arrays of length 11.

The ExUnit gate in [elixir/test/symphony_elixir/ndax_public_capability_gate_test.exs](../elixir/test/symphony_elixir/ndax_public_capability_gate_test.exs) enforces those fixture contracts.

## 1-Second Capture Decision

Decision: 1-second capture is feasible through public websocket event feeds, infeasible through REST polling.

Reason:

- The official NDAX support guide says REST is limited to 50 requests per minute, which is below the 60 requests per minute needed for 1-second polling.
- Public websocket probes showed event-driven updates faster than one second on the order-book surface.
- A manual public trades probe observed a `TradeDataUpdateEvent` during testing, so public tape-style streaming is available.
- `SubscribeTicker` does not support a 1-second bar interval, so 1-second capture must not be designed around ticker bars.

## Scope Stop

This issue proves a dry-run public market-data boundary only. It does not authorize auth, private endpoints, collectors, schedulers, listeners, storage daemons, or trading behavior.
