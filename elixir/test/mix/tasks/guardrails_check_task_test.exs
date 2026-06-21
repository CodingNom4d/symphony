defmodule Mix.Tasks.Guardrails.CheckTaskTest do
  use ExUnit.Case, async: false

  import ExUnit.CaptureIO

  alias Mix.Tasks.Guardrails.Check
  alias SymphonyElixir.BoundaryGuardrails

  setup do
    Mix.Task.reenable("guardrails.check")
    :ok
  end

  test "documents the governed paths, module namespaces, and exclusions" do
    policy = BoundaryGuardrails.policy()

    assert "lib/symphony_elixir/trading_view" in policy.governed_paths
    assert "lib/symphony_elixir/replay" in policy.governed_paths
    assert "test/symphony_elixir/backtest" in policy.governed_paths

    assert "SymphonyElixir.TradingView" in policy.governed_modules
    assert "SymphonyElixir.Replay" in policy.governed_modules
    assert "SymphonyElixir.Backtest" in policy.governed_modules

    assert "docs/private" in policy.excluded_paths
    assert "docs/superpowers" in policy.excluded_paths
    assert "test/support" in policy.excluded_paths
  end

  test "passes when no governed files exist" do
    in_temp_project(fn ->
      output =
        capture_io(fn ->
          assert :ok = Check.run([])
        end)

      assert output =~ "guardrails.check: dry-run boundary rules passed"
    end)
  end

  test "raises with actionable output for an intentionally bad fixture name" do
    in_temp_project(fn ->
      write_file!("lib/symphony_elixir/trading_view/ndax_private_client.ex", """
      defmodule SymphonyElixir.TradingView.NdaxPrivateClient do
        def endpoint, do: "/Account/GetBalances"
      end
      """)

      error_output =
        capture_io(:stderr, fn ->
          assert_raise Mix.Error, ~r/guardrails.check failed with 1 finding/, fn ->
            Check.run([])
          end
        end)

      assert error_output =~ "lib/symphony_elixir/trading_view/ndax_private_client.ex"
      assert error_output =~ "ndax private/account/trading surface"
    end)
  end

  defp in_temp_project(fun) do
    root =
      Path.join(
        System.tmp_dir!(),
        "guardrails-check-task-test-#{System.unique_integer([:positive, :monotonic])}"
      )

    original_cwd = File.cwd!()

    File.rm_rf!(root)
    File.mkdir_p!(root)

    try do
      File.cd!(root, fun)
    after
      File.cd!(original_cwd)
      File.rm_rf!(root)
    end
  end

  defp write_file!(path, source) do
    File.mkdir_p!(Path.dirname(path))
    File.write!(path, source)
  end
end
