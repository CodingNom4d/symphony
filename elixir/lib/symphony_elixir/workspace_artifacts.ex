defmodule SymphonyElixir.WorkspaceArtifacts do
  @moduledoc """
  Probes a workspace git status to summarize reviewable untracked artifacts.
  """

  alias SymphonyElixir.SSH

  @cache_table :symphony_workspace_artifacts_cache
  @cache_ttl_ms 5_000
  @generated_segments MapSet.new(["_build", "build", "cover", "deps", "node_modules", "tmp"])
  @generated_prefixes ["assets/build/", "assets/node_modules/", "priv/static/"]
  @summary_limit 5
  @local_probe_timeout_ms 1_000
  @remote_probe_timeout_ms 1_000
  @empty %{
    reviewable_untracked_count: 0,
    reviewable_untracked_paths: [],
    reviewable_untracked_summary: [],
    generated_untracked_count: 0,
    generated_untracked_paths: [],
    generated_untracked_summary: [],
    ignored_untracked_count: 0,
    ignored_untracked_paths: [],
    ignored_untracked_summary: [],
    probe_error: nil
  }

  @spec empty() :: map()
  def empty, do: @empty

  @spec probe(String.t() | nil) :: map()
  def probe(workspace_path), do: probe(workspace_path, nil)

  @spec cached_probe(String.t() | nil) :: map() | nil
  def cached_probe(workspace_path), do: cached_probe(workspace_path, nil)

  @spec cached_probe(String.t() | nil, String.t() | nil) :: map() | nil
  def cached_probe(workspace_path, _worker_host) when not is_binary(workspace_path) or workspace_path == "" do
    nil
  end

  def cached_probe(workspace_path, worker_host) do
    ensure_cache_table!()
    key = {workspace_path, worker_host}
    now_ms = System.monotonic_time(:millisecond)

    case :ets.lookup(@cache_table, key) do
      [{^key, artifacts, refreshed_at_ms, refreshing?}] ->
        if stale?(refreshed_at_ms, now_ms) and not refreshing? do
          mark_refreshing!(key, artifacts, refreshed_at_ms)
          refresh_async(key, workspace_path, worker_host)
        end

        artifacts

      [] ->
        artifacts = Map.put(@empty, :probe_error, "workspace artifact probe pending")
        :ets.insert(@cache_table, {key, artifacts, now_ms, true})
        refresh_async(key, workspace_path, worker_host)
        artifacts
    end
  end

  @spec probe(String.t() | nil, String.t() | nil) :: map()
  def probe(workspace_path, _worker_host) when not is_binary(workspace_path) or workspace_path == "" do
    @empty
  end

  def probe(workspace_path, worker_host) do
    case git_status(workspace_path, worker_host) do
      {:ok, lines} ->
        classify_lines(lines)

      {:error, reason} ->
        Map.put(@empty, :probe_error, error_message(reason))
    end
  end

  defp git_status(workspace_path, nil) do
    if File.dir?(workspace_path) do
      case System.find_executable("git") do
        nil ->
          {:error, :git_not_found}

        git ->
          workspace_path
          |> run_local_git_status(git)
          |> normalize_git_status_result()
      end
    else
      {:error, {:git_status_failed, :missing_workspace}}
    end
  end

  defp git_status(workspace_path, worker_host) when is_binary(worker_host) and worker_host != "" do
    workspace_path
    |> run_remote_git_status(worker_host)
    |> normalize_remote_git_status_result()
  end

  defp status_args do
    ["status", "--porcelain=v1", "--ignored=matching", "--untracked-files=all"]
  end

  defp classify_lines(lines) when is_list(lines) do
    classified =
      Enum.reduce(lines, %{reviewable: [], generated: [], ignored: []}, fn line, acc ->
        classify_line(String.trim_trailing(line), acc)
      end)

    reviewable = Enum.sort(classified.reviewable)
    generated = Enum.sort(classified.generated)
    ignored = Enum.sort(classified.ignored)

    %{
      reviewable_untracked_count: length(reviewable),
      reviewable_untracked_paths: reviewable,
      reviewable_untracked_summary: Enum.take(reviewable, @summary_limit),
      generated_untracked_count: length(generated),
      generated_untracked_paths: generated,
      generated_untracked_summary: Enum.take(generated, @summary_limit),
      ignored_untracked_count: length(ignored),
      ignored_untracked_paths: ignored,
      ignored_untracked_summary: Enum.take(ignored, @summary_limit),
      probe_error: nil
    }
  end

  defp classify_line("?? " <> path, acc) do
    if generated_path?(path) do
      Map.update!(acc, :generated, &[path | &1])
    else
      Map.update!(acc, :reviewable, &[path | &1])
    end
  end

  defp classify_line("!! " <> path, acc) do
    Map.update!(acc, :ignored, &[path | &1])
  end

  defp classify_line(_line, acc), do: acc

  defp generated_path?(path) when is_binary(path) do
    normalized = String.replace(path, "\\", "/")
    segments = String.split(normalized, "/", trim: true)

    Enum.any?(@generated_prefixes, &String.starts_with?(normalized, &1)) or
      Enum.any?(segments, &MapSet.member?(@generated_segments, &1))
  end

  defp ensure_cache_table! do
    case :ets.whereis(@cache_table) do
      :undefined ->
        :ets.new(@cache_table, [:named_table, :public, read_concurrency: true, write_concurrency: true])

      _table ->
        @cache_table
    end
  end

  defp stale?(refreshed_at_ms, now_ms) when is_integer(refreshed_at_ms) do
    now_ms - refreshed_at_ms >= @cache_ttl_ms
  end

  defp mark_refreshing!(key, artifacts, refreshed_at_ms) do
    :ets.insert(@cache_table, {key, artifacts, refreshed_at_ms, true})
  end

  defp refresh_async(key, workspace_path, worker_host) do
    Task.start(fn ->
      artifacts = probe(workspace_path, worker_host)
      :ets.insert(@cache_table, {key, artifacts, System.monotonic_time(:millisecond), false})
    end)

    :ok
  end

  defp error_message(:git_not_found), do: "git executable not available"
  defp error_message(:ssh_not_found), do: "ssh executable not available"
  defp error_message({:git_status_failed, status}), do: "git status failed with exit #{inspect(status)}"
  defp error_message(reason), do: "workspace artifact probe failed: #{inspect(reason)}"

  defp run_local_git_status(workspace_path, git) when is_binary(workspace_path) and is_binary(git) do
    run_with_timeout(@local_probe_timeout_ms, fn ->
      System.cmd(git, status_args(), cd: workspace_path, stderr_to_stdout: true)
    end)
  end

  defp normalize_git_status_result({output, 0}) do
    {:ok, String.split(output, ~r/\r\n|\r|\n/, trim: true)}
  end

  defp normalize_git_status_result({_output, status}) when is_integer(status) do
    {:error, {:git_status_failed, status}}
  end

  defp normalize_git_status_result({:error, reason}), do: {:error, reason}

  defp normalize_remote_git_status_result({:ok, cmd_result}), do: normalize_git_status_result(cmd_result)
  defp normalize_remote_git_status_result({:error, reason}), do: {:error, reason}

  defp run_with_timeout(timeout_ms, fun) when is_integer(timeout_ms) and timeout_ms > 0 and is_function(fun, 0) do
    task = Task.async(fun)

    case Task.yield(task, timeout_ms) || Task.shutdown(task, :brutal_kill) do
      {:ok, result} -> result
      nil -> {:error, :probe_timeout}
    end
  end

  defp run_remote_git_status(workspace_path, worker_host)
       when is_binary(workspace_path) and is_binary(worker_host) do
    command = "cd #{shell_escape(workspace_path)} && git #{Enum.join(status_args(), " ")}"
    run_with_timeout(@remote_probe_timeout_ms, fn -> SSH.run(worker_host, command, stderr_to_stdout: true) end)
  end

  defp shell_escape(value) when is_binary(value) do
    "'" <> String.replace(value, "'", "'\"'\"'") <> "'"
  end
end
