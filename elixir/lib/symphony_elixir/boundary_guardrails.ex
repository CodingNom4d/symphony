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

  @required_checkpoint_doc "docs/tradingview/signal-envelope-checkpoint.md"
  @signal_schema_version "tv.signal-envelope.v1"
  @fixture_dir "docs/tradingview/fixtures"
  @checkpoint_required_phrases [
    "tv.signal-envelope.v1",
    "signal_ref",
    "eligible_rows",
    "audit-only evidence"
  ]

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

  @execution_language_patterns [
    ~r/\b(live order|place order|submit order|send order|order routing|execution ready|execute trade)\b/i
  ]

  @audit_only_key_patterns [
    ~r/^nearest_quote_after$/,
    ~r/^stale_.+/,
    ~r/^future_.+/
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
    project_root = Path.expand(project_root)

    ((project_root
      |> governed_files()
      |> Enum.flat_map(&file_findings(project_root, &1))) ++ required_checkpoint_findings(project_root))
    |> Enum.sort_by(&{&1.path, &1.line, &1.rule, &1.snippet})
  end

  defp governed_files(project_root) do
    policy()
    |> Map.fetch!(:governed_paths)
    |> Enum.flat_map(&expand_governed_root(project_root, &1))
    |> Enum.reject(fn {relative_path, _absolute_path} -> excluded?(relative_path) end)
    |> Enum.uniq()
  end

  defp expand_governed_root(project_root, rel_path) do
    case resolve_governed_root(project_root, rel_path) do
      nil -> []
      {canonical_root, absolute_root} -> expand_resolved_root(canonical_root, absolute_root)
    end
  end

  defp expand_resolved_root(canonical_root, absolute_root) do
    cond do
      File.regular?(absolute_root) ->
        [{canonical_root, absolute_root}]

      File.dir?(absolute_root) ->
        absolute_root
        |> Path.join("**/*")
        |> Path.wildcard()
        |> Enum.filter(&File.regular?/1)
        |> Enum.map(fn absolute_path ->
          {join_relative(canonical_root, Path.relative_to(absolute_path, absolute_root)), absolute_path}
        end)

      true ->
        []
    end
  end

  defp resolve_governed_root(project_root, rel_path) do
    direct = Path.join(project_root, rel_path)

    cond do
      File.exists?(direct) ->
        {rel_path, direct}

      String.starts_with?(rel_path, "docs/") ->
        parent = Path.expand(Path.join(["..", rel_path]), project_root)

        if File.exists?(parent) do
          {rel_path, parent}
        end

      true ->
        nil
    end
  end

  defp excluded?(relative_path) do
    Enum.any?(policy().excluded_paths, fn excluded_path ->
      relative_path == excluded_path || String.starts_with?(relative_path, excluded_path <> "/")
    end)
  end

  defp file_findings(project_root, {relative_path, absolute_path}) do
    source = File.read!(absolute_path)

    cond do
      fixture_json?(relative_path) ->
        json_fixture_findings(project_root, relative_path, absolute_path, source)

      relative_path == @required_checkpoint_doc ->
        validate_checkpoint_doc(relative_path, source)

      markdown_doc?(relative_path) ->
        []

      true ->
        [
          scan_text_rule(
            relative_path,
            source,
            :ndax_private_surface,
            "ndax private/account/trading surface",
            @ndax_private_patterns
          ),
          scan_text_rule(
            relative_path,
            source,
            :questrade_auth_account,
            "questrade auth/account implementation",
            @questrade_patterns,
            2
          ),
          scan_text_rule(
            relative_path,
            source,
            :credential_material,
            "credential or account identifier material",
            @credential_patterns
          ),
          scan_text_rule(
            relative_path,
            source,
            :webhook_persistence,
            "secret-like webhook persistence or raw request storage",
            @webhook_persistence_patterns
          ),
          scan_text_rule(
            relative_path,
            source,
            :listener_or_scheduler,
            "listener, scheduler, daemon, tunnel, or service creation",
            @listener_patterns
          ),
          scan_import_rule(relative_path, source)
        ]
        |> Enum.reject(&is_nil/1)
    end
  end

  defp json_fixture_findings(project_root, relative_path, absolute_path, source) do
    case Jason.decode(source) do
      {:ok, json} when is_map(json) ->
        [
          validate_signal_schema_version(relative_path, source, json),
          validate_replay_manifest(project_root, relative_path, absolute_path, source, json),
          validate_export_hygiene(relative_path, source, json)
        ]
        |> List.flatten()
        |> Enum.reject(&is_nil/1)

      {:ok, _json} ->
        [
          finding(
            relative_path,
            1,
            :fixture_json_parse,
            "fixture JSON root must be an object",
            first_line(source)
          )
        ]

      {:error, error} ->
        [
          finding(
            relative_path,
            1,
            :fixture_json_parse,
            "fixture JSON does not parse",
            Exception.message(error)
          )
        ]
    end
  end

  defp validate_signal_schema_version(relative_path, source, json) do
    if Map.get(json, "signal_schema_version") == @signal_schema_version do
      nil
    else
      finding(
        relative_path,
        find_line(source, "signal_schema_version"),
        :signal_schema_version,
        "fixture must declare signal_schema_version #{@signal_schema_version}",
        "\"signal_schema_version\""
      )
    end
  end

  defp validate_replay_manifest(project_root, relative_path, absolute_path, source, json) do
    if replay_manifest?(relative_path) do
      signal_ref = Map.get(json, "signal_ref")

      case signal_ref do
        %{"fixture_alias" => fixture_alias, "envelope_fixture" => envelope_fixture}
        when is_binary(fixture_alias) and is_binary(envelope_fixture) ->
          [
            validate_envelope_fixture_exists(relative_path, absolute_path, source, envelope_fixture),
            validate_signal_ref_alias(relative_path, absolute_path, source, fixture_alias, envelope_fixture),
            validate_eligible_rows(project_root, relative_path, source, json)
          ]

        _other ->
          [
            finding(
              relative_path,
              find_line(source, "signal_ref"),
              :signal_ref_shape,
              "replay manifest signal_ref must be an object with fixture_alias and envelope_fixture",
              "\"signal_ref\""
            )
          ]
      end
    else
      []
    end
  end

  defp validate_envelope_fixture_exists(relative_path, absolute_path, source, envelope_fixture) do
    envelope_path = Path.join(Path.dirname(absolute_path), envelope_fixture)

    if File.exists?(envelope_path) do
      nil
    else
      finding(
        relative_path,
        find_line(source, envelope_fixture),
        :missing_envelope_fixture,
        "replay manifest references a missing signal-envelope fixture",
        envelope_fixture
      )
    end
  end

  defp validate_signal_ref_alias(relative_path, absolute_path, source, fixture_alias, envelope_fixture) do
    envelope_path = Path.join(Path.dirname(absolute_path), envelope_fixture)

    with true <- File.exists?(envelope_path),
         {:ok, envelope_json} <- Jason.decode(File.read!(envelope_path)),
         %{"alias" => envelope_alias} <- Map.get(envelope_json, "operational_signal_ref"),
         true <- fixture_alias == envelope_alias do
      nil
    else
      false ->
        finding(
          relative_path,
          find_line(source, fixture_alias),
          :signal_ref_alias_mismatch,
          "replay manifest signal_ref.fixture_alias must match the referenced signal-envelope alias",
          fixture_alias
        )

      _other ->
        finding(
          relative_path,
          find_line(source, fixture_alias),
          :signal_ref_alias_mismatch,
          "referenced signal-envelope fixture must expose operational_signal_ref.alias",
          fixture_alias
        )
    end
  end

  defp validate_eligible_rows(_project_root, relative_path, source, json) do
    market_context = Map.get(json, "market_context", %{})
    eligible_rows = Map.get(market_context, "eligible_rows", [])
    decision_time = parse_datetime(Map.get(json, "decision_time"))
    staleness_seconds = parse_duration_seconds(get_in(market_context, ["staleness_threshold"]))

    eligible_rows
    |> Enum.flat_map(fn row ->
      violations = []
      available_at = parse_datetime(Map.get(row, "available_at_utc"))
      freshness_time = parse_datetime(Map.get(row, "source_event_time_utc")) || available_at
      row_id = Map.get(row, "row_id", "eligible_rows")
      row_snippet = row_id |> to_string()

      violations =
        if future_row?(available_at, decision_time) do
          [
            finding(
              relative_path,
              find_line(source, row_snippet),
              :future_or_stale_eligible_row,
              "eligible_rows must exclude future rows and rows older than staleness_threshold",
              row_snippet
            )
            | violations
          ]
        else
          violations
        end

      if stale_row?(freshness_time, decision_time, staleness_seconds) do
        [
          finding(
            relative_path,
            find_line(source, row_snippet),
            :future_or_stale_eligible_row,
            "eligible_rows must exclude future rows and rows older than staleness_threshold",
            row_snippet
          )
          | violations
        ]
      else
        violations
      end
    end)
  end

  defp validate_export_hygiene(relative_path, source, json) do
    case export_hygiene_violation(source, json) || audit_evidence_container_violation(source, json) do
      nil ->
        nil

      {snippet, line, rule} ->
        finding(
          relative_path,
          line,
          rule,
          "future/stale-only context must live under audit_evidence and stay out of strategy-eligible inputs",
          snippet
        )

      {snippet, line} ->
        finding(
          relative_path,
          line,
          :export_hygiene,
          "exported fixtures/manifests contain direct locators, provenance row ids, secret-like content, private endpoints, or execution language",
          snippet
        )
    end
  end

  defp export_hygiene_violation(source, json) do
    direct_locator_violation(json) || source_pattern_violation(source)
  end

  defp audit_evidence_container_violation(source, json) do
    market_context = Map.get(json, "market_context")

    case misplaced_audit_only_key(market_context) do
      nil ->
        nil

      key ->
        {key, find_line(source, key), :audit_evidence_container}
    end
  end

  defp direct_locator_violation(json) do
    [
      signal_ref_scope(json),
      {"operational_signal_ref", Map.get(json, "operational_signal_ref"), ~w(alias)},
      {"signal_provenance_ref", Map.get(json, "signal_provenance_ref"), ~w(kind alias)},
      {"decision_provenance_ref", Map.get(json, "decision_provenance_ref"), ~w(kind alias)}
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.find_value(&invalid_scope_value/1)
  end

  defp signal_ref_scope(json) do
    case Map.get(json, "signal_ref") do
      value when is_map(value) ->
        {"signal_ref", value, ~w(fixture_alias envelope_fixture)}

      _other ->
        nil
    end
  end

  defp invalid_scope_value({_scope, nil, _allowed_keys}), do: nil

  defp invalid_scope_value({scope, value, allowed_keys}) when is_map(value) do
    case Enum.find(Map.keys(value), &(&1 not in allowed_keys)) do
      nil -> nil
      key -> {"#{scope}.#{key}", 1}
    end
  end

  defp invalid_scope_value({scope, _value, _allowed_keys}), do: {scope, 1}

  defp misplaced_audit_only_key(value), do: misplaced_audit_only_key(value, [])

  defp misplaced_audit_only_key(value, path) when is_map(value) do
    value
    |> Enum.find_value(fn {key, nested_value} ->
      cond do
        audit_evidence_path?(path, key) ->
          nil

        audit_only_key?(key) ->
          key

        true ->
          misplaced_audit_only_key(nested_value, path ++ [key])
      end
    end)
  end

  defp misplaced_audit_only_key(value, path) when is_list(value) do
    value
    |> Enum.find_value(&misplaced_audit_only_key(&1, path))
  end

  defp misplaced_audit_only_key(_value, _path), do: nil

  defp audit_evidence_path?(path, key) do
    key == "audit_evidence" || "audit_evidence" in path
  end

  defp audit_only_key?(key) when is_binary(key) do
    Enum.any?(@audit_only_key_patterns, &Regex.match?(&1, key))
  end

  defp audit_only_key?(_key), do: false

  defp source_pattern_violation(source) do
    patterns =
      @ndax_private_patterns ++
        @credential_patterns ++ @webhook_persistence_patterns ++ @execution_language_patterns

    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.find_value(fn {line_text, line_number} ->
      if Enum.any?(patterns, &Regex.match?(&1, line_text)) do
        {String.trim(line_text), line_number}
      end
    end)
  end

  defp future_row?(%DateTime{} = available_at, %DateTime{} = decision_time) do
    DateTime.compare(available_at, decision_time) == :gt
  end

  defp future_row?(_available_at, _decision_time), do: false

  defp stale_row?(%DateTime{} = available_at, %DateTime{} = decision_time, seconds)
       when is_integer(seconds) and seconds >= 0 do
    DateTime.diff(decision_time, available_at, :second) > seconds
  end

  defp stale_row?(_available_at, _decision_time, _seconds), do: false

  defp parse_datetime(nil), do: nil

  defp parse_datetime(value) when is_binary(value) do
    case DateTime.from_iso8601(value) do
      {:ok, datetime, _offset} -> datetime
      _other -> nil
    end
  end

  defp parse_datetime(_value), do: nil

  defp parse_duration_seconds(nil), do: nil

  defp parse_duration_seconds("PT" <> rest) do
    case Regex.run(~r/^(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?$/, rest, capture: :all_but_first) do
      [hours, minutes, seconds] ->
        parse_part(hours, 3600) + parse_part(minutes, 60) + parse_part(seconds, 1)

      _other ->
        nil
    end
  end

  defp parse_duration_seconds(_value), do: nil

  defp parse_part("", _multiplier), do: 0
  defp parse_part(nil, _multiplier), do: 0

  defp parse_part(value, multiplier) do
    case Integer.parse(value) do
      {number, ""} -> number * multiplier
      _other -> 0
    end
  end

  defp scan_text_rule(relative_path, source, rule, message, patterns, min_matches \\ 1) do
    matches =
      line_matches(source, patterns)
      |> Enum.take(min_matches)

    if length(matches) >= min_matches do
      %{line: line, snippet: snippet} = List.last(matches)

      finding(relative_path, line, rule, message, snippet)
    end
  end

  defp line_matches(source, patterns) do
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
          finding(
            relative_path,
            line,
            :replay_import_boundary,
            "replay/backtest/strategy path imports network, private, or execution code",
            snippet
          )
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

  defp fixture_json?(relative_path) do
    String.starts_with?(relative_path, @fixture_dir <> "/") and String.ends_with?(relative_path, ".json")
  end

  defp markdown_doc?(relative_path) do
    String.ends_with?(relative_path, ".md")
  end

  defp required_checkpoint_findings(project_root) do
    if exported_tradingview_fixtures_present?(project_root) do
      case resolve_governed_root(project_root, @required_checkpoint_doc) do
        nil ->
          [
            finding(
              @required_checkpoint_doc,
              1,
              :checkpoint_doc_missing,
              "required checkpoint documentation file is missing",
              @required_checkpoint_doc
            )
          ]

        _present ->
          []
      end
    else
      []
    end
  end

  defp validate_checkpoint_doc(relative_path, source) do
    @checkpoint_required_phrases
    |> Enum.find(&(not String.contains?(source, &1)))
    |> case do
      nil ->
        []

      missing_phrase ->
        [
          finding(
            relative_path,
            find_line(source, missing_phrase),
            :checkpoint_doc_contract,
            "checkpoint documentation is missing a required contract phrase",
            missing_phrase
          )
        ]
    end
  end

  defp replay_manifest?(relative_path) do
    String.ends_with?(relative_path, ".manifest.json")
  end

  defp exported_tradingview_fixtures_present?(project_root) do
    case resolve_governed_root(project_root, @fixture_dir) do
      {_relative_path, fixture_dir} when is_binary(fixture_dir) -> File.dir?(fixture_dir)
      _other -> false
    end
  end

  defp find_line(source, needle) do
    source
    |> String.split("\n")
    |> Enum.with_index(1)
    |> Enum.find_value(1, fn {line_text, line_number} ->
      if String.contains?(line_text, needle), do: line_number
    end)
  end

  defp first_line(source) do
    source
    |> String.split("\n")
    |> List.first()
    |> to_string()
    |> String.trim()
  end

  defp join_relative(root, child) do
    [root, child]
    |> Enum.reject(&(&1 in ["", "."]))
    |> Enum.join("/")
  end

  defp finding(path, line, rule, message, snippet) do
    %{
      path: path,
      line: line,
      rule: rule,
      message: message,
      snippet: snippet
    }
  end
end
