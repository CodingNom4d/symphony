defmodule SymphonyElixir.BoundaryGuardrails do
  @moduledoc false

  @typedoc "A single dry-run boundary violation."
  @type finding :: %{
          path: String.t(),
          line: pos_integer(),
          rule: atom(),
          message: String.t(),
          snippet: String.t()
        }

  @typedoc "Static policy describing the dry-run surface this suite governs."
  @type policy :: %{
          governed_paths: [String.t()],
          governed_modules: [String.t()],
          excluded_paths: [String.t()]
        }

  @policy %{
    governed_paths: [
      "lib/symphony_elixir/trading_view",
      "lib/symphony_elixir/tradingview",
      "lib/symphony_elixir/dry_run",
      "lib/symphony_elixir/replay",
      "lib/symphony_elixir/backtest",
      "lib/symphony_elixir/strategy",
      "test/symphony_elixir/trading_view",
      "test/symphony_elixir/tradingview",
      "test/symphony_elixir/dry_run",
      "test/symphony_elixir/replay",
      "test/symphony_elixir/backtest",
      "test/symphony_elixir/strategy",
      "docs/tradingview",
      "docs/dry_run"
    ],
    governed_modules: [
      "SymphonyElixir.TradingView",
      "SymphonyElixir.Tradingview",
      "SymphonyElixir.DryRun",
      "SymphonyElixir.Replay",
      "SymphonyElixir.Backtest",
      "SymphonyElixir.Strategy"
    ],
    excluded_paths: [
      "docs/private",
      "docs/superpowers",
      "test/support",
      "test/fixtures/boundary_guardrails/allowed",
      "test/fixtures/boundary_guardrails/violations",
      "lib/symphony_elixir/linear",
      "lib/symphony_elixir/config",
      "lib/symphony_elixir/http_server.ex",
      "lib/symphony_elixir/orchestrator.ex",
      "lib/symphony_elixir/status_dashboard.ex",
      "lib/symphony_elixir/workflow_store.ex",
      "lib/symphony_elixir_web"
    ]
  }

  @ndax_private_patterns [
    ~r/ndax[_\W]*(private|account|trading|auth|order|withdraw|deposit|balance|position)/i,
    ~r{/(Account|Auth|Order|Orders|Trade|Trades|Balances|Positions|Withdraw|Deposit)(/|$)}i
  ]

  @questrade_patterns [
    ~r/questrade/i,
    ~r/(refresh[_-]?token|access[_-]?token|account[_-]?(id|number)|oauth|login|auth[_-]?client)/i
  ]

  @credential_patterns [
    ~r/\b(api[_-]?key|secret|token|signature|signed[_-]?request|auth[_-]?client)\b/i,
    ~r/\b(broker|exchange)[_-]?account[_-]?(id|identifier|number)\b/i,
    ~r/\b(NDAX|QUESTRADE)_[A-Z0-9_]*(KEY|SECRET|TOKEN|ACCOUNT)\b/
  ]

  @webhook_persistence_patterns [
    ~r/\b(webhook[_-]?(secret|token)|x-ndax-signature|x-signature)\b/i,
    ~r/\b(raw[_-]?body|request[_-]?headers?|headers|query[_-]?string|cookies?)\b/i
  ]

  @listener_patterns [
    ~r/\b(Bandit|Plug\.Cowboy|Phoenix\.Endpoint|ngrok)\b/,
    ~r/\b(GenServer|Task\.start|Task\.async|Process\.send_after|:timer\.send_interval)\b/,
    ~r/\b(listener|scheduler|daemon|service|worker|tunnel)\b/i
  ]

  @forbidden_import_prefixes [
    "Req",
    "Finch",
    "HTTPoison",
    "Tesla",
    "Mint",
    "SymphonyElixir.Linear.Client",
    "SymphonyElixir.HttpServer",
    "SymphonyElixir.Execution",
    "SymphonyElixir.Order",
    "SymphonyElixir.Broker",
    "SymphonyElixir.Exchange",
    "SymphonyElixir.Ndax",
    "SymphonyElixir.Questrade"
  ]

  @spec policy() :: policy()
  def policy, do: @policy

  @spec findings(Path.t()) :: [finding()]
  def findings(project_root) when is_binary(project_root) do
    project_root
    |> governed_files()
    |> Enum.flat_map(&file_findings(project_root, &1))
    |> Enum.sort_by(&{&1.path, &1.line, &1.rule, &1.snippet})
  end

  defp governed_files(project_root) do
    project_root = Path.expand(project_root)

    policy()
    |> Map.fetch!(:governed_paths)
    |> Enum.flat_map(fn rel_path ->
      absolute_path = Path.join(project_root, rel_path)

      cond do
        File.regular?(absolute_path) -> [absolute_path]
        File.dir?(absolute_path) -> Path.wildcard(Path.join(absolute_path, "**/*"))
        true -> []
      end
    end)
    |> Enum.filter(&File.regular?/1)
    |> Enum.uniq()
    |> Enum.reject(&excluded?(project_root, &1))
  end

  defp excluded?(project_root, absolute_path) do
    relative_path = relative_path(project_root, absolute_path)

    Enum.any?(policy().excluded_paths, fn excluded_path ->
      relative_path == excluded_path || String.starts_with?(relative_path, excluded_path <> "/")
    end)
  end

  defp file_findings(project_root, absolute_path) do
    relative_path = relative_path(project_root, absolute_path)
    source = File.read!(absolute_path)

    [
      scan_text_rule(relative_path, source, :ndax_private_surface, "ndax private/account/trading surface", @ndax_private_patterns),
      scan_text_rule(relative_path, source, :questrade_auth_account, "questrade auth/account implementation", @questrade_patterns, 2),
      scan_text_rule(relative_path, source, :credential_material, "credential or account identifier material", @credential_patterns),
      scan_text_rule(relative_path, source, :webhook_persistence, "secret-like webhook persistence or raw request storage", @webhook_persistence_patterns),
      scan_text_rule(relative_path, source, :listener_or_scheduler, "listener, scheduler, daemon, tunnel, or service creation", @listener_patterns),
      scan_import_rule(relative_path, source)
    ]
    |> Enum.reject(&is_nil/1)
  end

  defp scan_text_rule(relative_path, source, rule, message, patterns, min_matches \\ 1) do
    matches =
      line_matches(relative_path, source, patterns)
      |> Enum.take(min_matches)

    if length(matches) >= min_matches do
      %{line: line, snippet: snippet} = List.last(matches)

      %{
        path: relative_path,
        line: line,
        rule: rule,
        message: message,
        snippet: snippet
      }
    end
  end

  defp line_matches(_relative_path, source, patterns) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.flat_map(fn {line_text, line_number} ->
      if Enum.any?(patterns, &Regex.match?(&1, line_text)) do
        [%{line: line_number, snippet: String.trim(line_text)}]
      else
        []
      end
    end)
  end

  defp scan_import_rule(relative_path, source) do
    if replay_like_path?(relative_path) do
      relative_path
      |> import_findings(source)
      |> Enum.sort_by(&{&1.line, &1.snippet})
      |> List.first()
      |> case do
        nil ->
          nil

        %{line: line, snippet: snippet} ->
          %{
            path: relative_path,
            line: line,
            rule: :replay_import_boundary,
            message: "replay/backtest/strategy path imports network, private, or execution code",
            snippet: snippet
          }
      end
    end
  end

  defp import_findings(relative_path, source) do
    case Code.string_to_quoted(source, columns: true, file: relative_path) do
      {:ok, ast} ->
        {_ast, findings} =
          Macro.prewalk(ast, [], fn
            {:alias, meta, args} = node, acc ->
              {node, maybe_add_alias_reference(args, meta, acc)}

            {:import, meta, args} = node, acc ->
              {node, maybe_add_alias_reference(args, meta, acc)}

            {:require, meta, args} = node, acc ->
              {node, maybe_add_alias_reference(args, meta, acc)}

            {:use, meta, args} = node, acc ->
              {node, maybe_add_alias_reference(args, meta, acc)}

            {{:., meta, [{:__aliases__, _, parts}, _function]}, _, _} = node, acc ->
              module_name = Enum.join(parts, ".")
              {node, maybe_add_import_finding(module_name, meta, acc)}

            node, acc ->
              {node, acc}
          end)

        Enum.reverse(findings)

      {:error, _reason} ->
        []
    end
  end

  defp maybe_add_alias_reference([{:__aliases__, meta, parts} | _rest], _node_meta, acc) do
    module_name = Enum.join(parts, ".")
    maybe_add_import_finding(module_name, meta, acc)
  end

  defp maybe_add_alias_reference(_args, _meta, acc), do: acc

  defp maybe_add_import_finding(module_name, meta, acc) do
    if Enum.any?(@forbidden_import_prefixes, &String.starts_with?(module_name, &1)) do
      [%{line: Keyword.get(meta, :line, 1), snippet: module_name} | acc]
    else
      acc
    end
  end

  defp replay_like_path?(relative_path) do
    Enum.any?(["/replay/", "/backtest/", "/strategy/"], &String.contains?(relative_path, &1))
  end

  defp relative_path(project_root, absolute_path) do
    absolute_path
    |> Path.expand()
    |> Path.relative_to(project_root)
    |> Path.split()
    |> Enum.join("/")
  end
end
