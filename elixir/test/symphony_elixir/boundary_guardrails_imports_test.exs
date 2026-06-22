defmodule SymphonyElixir.BoundaryGuardrailsImportsTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.BoundaryGuardrails

  test "flags replay and backtest imports of forbidden modules" do
    in_temp_project(fn root ->
      write_file!(root, "lib/symphony_elixir/replay/req_client.ex", """
      defmodule SymphonyElixir.Replay.ReqClient do
        alias Req
      end
      """)

      write_file!(root, "lib/symphony_elixir/backtest/linear_client.ex", """
      defmodule SymphonyElixir.Backtest.LinearClient do
        import SymphonyElixir.Linear.Client
      end
      """)

      write_file!(root, "lib/symphony_elixir/strategy/http_server.ex", """
      defmodule SymphonyElixir.Strategy.HttpServer do
        require SymphonyElixir.HttpServer
      end
      """)

      write_file!(root, "lib/symphony_elixir/replay/network_use.ex", """
      defmodule SymphonyElixir.Replay.NetworkUse do
        use SymphonyElixir.Ndax.PublicClient
      end
      """)

      write_file!(root, "lib/symphony_elixir/backtest/direct_call.ex", """
      defmodule SymphonyElixir.Backtest.DirectCall do
        def fetch(url), do: Req.get!(url)
      end
      """)

      findings = BoundaryGuardrails.findings(root)

      assert_rule(findings, "lib/symphony_elixir/replay/req_client.ex")
      assert_rule(findings, "lib/symphony_elixir/backtest/linear_client.ex")
      assert_rule(findings, "lib/symphony_elixir/strategy/http_server.ex")
      assert_rule(findings, "lib/symphony_elixir/replay/network_use.ex")
      assert_rule(findings, "lib/symphony_elixir/backtest/direct_call.ex")

      assert Enum.all?(findings, &(not String.contains?(&1.path, "\\")))
    end)
  end

  test "allows replay and backtest files that stay within pure local modules" do
    in_temp_project(fn root ->
      write_file!(root, "lib/symphony_elixir/replay/pure_transform.ex", """
      defmodule SymphonyElixir.Replay.PureTransform do
        alias SymphonyElixir.Replay.CanonicalPayload

        def normalize(payload), do: CanonicalPayload.normalize(payload)
      end
      """)

      write_file!(root, "lib/symphony_elixir/backtest/pure_projection.ex", """
      defmodule SymphonyElixir.Backtest.PureProjection do
        def project(series), do: Enum.map(series, & &1)
      end
      """)

      findings =
        BoundaryGuardrails.findings(root)
        |> Enum.filter(&(&1.rule == :replay_import_boundary))

      assert findings == []
    end)
  end

  defp assert_rule(findings, path) do
    assert Enum.any?(findings, fn finding ->
             finding.path == path and finding.rule == :replay_import_boundary
           end),
           "expected #{path} to report :replay_import_boundary, got #{inspect(findings)}"
  end

  defp in_temp_project(fun) do
    root =
      Path.join(
        System.tmp_dir!(),
        "boundary-guardrails-imports-test-#{System.unique_integer([:positive, :monotonic])}"
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
