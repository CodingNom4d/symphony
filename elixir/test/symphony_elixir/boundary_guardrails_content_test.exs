defmodule SymphonyElixir.BoundaryGuardrailsContentTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.BoundaryGuardrails

  test "reports forbidden content and allows clean dry-run files" do
    in_temp_project(fn root ->
      write_file!(root, "lib/symphony_elixir/trading_view/market_data_client.ex", """
      defmodule SymphonyElixir.TradingView.MarketDataClient do
        def latest_ticker(symbol), do: {:ok, symbol}
      end
      """)

      write_file!(root, "lib/symphony_elixir/trading_view/ndax_private_client.ex", """
      defmodule SymphonyElixir.TradingView.NdaxPrivateClient do
        def endpoint, do: "/Account/GetBalances"
      end
      """)

      write_file!(root, "lib/symphony_elixir/dry_run/questrade_auth.ex", """
      defmodule SymphonyElixir.DryRun.QuestradeAuth do
        def login(refresh_token, account_number), do: {refresh_token, account_number}
      end
      """)

      write_file!(root, "lib/symphony_elixir/dry_run/credential_material.ex", """
      defmodule SymphonyElixir.DryRun.CredentialMaterial do
        @ndax_api_key System.get_env("NDAX_API_KEY")
        def signer(secret, signed_request), do: {secret, signed_request}
      end
      """)

      write_file!(root, "lib/symphony_elixir/dry_run/webhook_store.ex", """
      defmodule SymphonyElixir.DryRun.WebhookStore do
        def persist(raw_body, request_headers, query_string, cookies, webhook_secret) do
          {raw_body, request_headers, query_string, cookies, webhook_secret}
        end
      end
      """)

      write_file!(root, "lib/symphony_elixir/dry_run/listener_service.ex", """
      defmodule SymphonyElixir.DryRun.ListenerService do
        use GenServer

        def start_link do
          Process.send_after(self(), :tick, 5_000)
          GenServer.start_link(__MODULE__, :ok)
        end
      end
      """)

      findings = BoundaryGuardrails.findings(root)

      refute Enum.any?(findings, &(&1.path == "lib/symphony_elixir/trading_view/market_data_client.ex"))

      assert_rule(findings, "lib/symphony_elixir/trading_view/ndax_private_client.ex", :ndax_private_surface)

      assert_rule(
        findings,
        "lib/symphony_elixir/dry_run/questrade_auth.ex",
        :questrade_auth_account
      )

      assert_rule(
        findings,
        "lib/symphony_elixir/dry_run/credential_material.ex",
        :credential_material
      )

      assert_rule(
        findings,
        "lib/symphony_elixir/dry_run/webhook_store.ex",
        :webhook_persistence
      )

      assert_rule(
        findings,
        "lib/symphony_elixir/dry_run/listener_service.ex",
        :listener_or_scheduler
      )
    end)
  end

  defp assert_rule(findings, path, rule) do
    assert Enum.any?(findings, fn finding -> finding.path == path and finding.rule == rule end),
           "expected #{path} to report #{inspect(rule)}, got #{inspect(findings)}"
  end

  defp in_temp_project(fun) do
    root =
      Path.join(
        System.tmp_dir!(),
        "boundary-guardrails-content-test-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.rm_rf!(root)
    File.mkdir_p!(root)

    try do
      fun.(root)
    after
      File.rm_rf!(root)
    end
  end

  defp write_file!(root, rel_path, source) do
    path = Path.join(root, rel_path)
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, source)
  end
end
