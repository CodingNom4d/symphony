defmodule SymphonyElixirWeb.Presenter do
  @moduledoc """
  Shared projections for the observability API and dashboard.
  """

  alias SymphonyElixir.{Config, Orchestrator, StatusDashboard, WorkEfficiency, WorkspaceArtifacts}

  @spec state_payload(GenServer.name(), timeout()) :: map()
  def state_payload(orchestrator, snapshot_timeout_ms) do
    generated_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    case Orchestrator.snapshot(orchestrator, snapshot_timeout_ms) do
      %{} = snapshot ->
        snapshot = enrich_snapshot(snapshot)

        %{
          generated_at: generated_at,
          counts: %{
            running: length(snapshot.running),
            retrying: length(snapshot.retrying),
            blocked: length(Map.get(snapshot, :blocked, []))
          },
          running: Enum.map(snapshot.running, &running_entry_payload/1),
          retrying: Enum.map(snapshot.retrying, &retry_entry_payload/1),
          blocked: Enum.map(Map.get(snapshot, :blocked, []), &blocked_entry_payload/1),
          codex_totals: snapshot.codex_totals,
          work_efficiency: Map.get(snapshot, :work_efficiency),
          rate_limits: snapshot.rate_limits
        }

      :timeout ->
        %{generated_at: generated_at, error: %{code: "snapshot_timeout", message: "Snapshot timed out"}}

      :unavailable ->
        %{generated_at: generated_at, error: %{code: "snapshot_unavailable", message: "Snapshot unavailable"}}
    end
  end

  @spec issue_payload(String.t(), GenServer.name(), timeout()) :: {:ok, map()} | {:error, :issue_not_found}
  def issue_payload(issue_identifier, orchestrator, snapshot_timeout_ms) when is_binary(issue_identifier) do
    case Orchestrator.snapshot(orchestrator, snapshot_timeout_ms) do
      %{} = snapshot ->
        snapshot = enrich_snapshot(snapshot)
        running = Enum.find(snapshot.running, &(&1.identifier == issue_identifier))
        retry = Enum.find(snapshot.retrying, &(&1.identifier == issue_identifier))
        blocked = Enum.find(Map.get(snapshot, :blocked, []), &(&1.identifier == issue_identifier))

        if is_nil(running) and is_nil(retry) and is_nil(blocked) do
          {:error, :issue_not_found}
        else
          {:ok, issue_payload_body(issue_identifier, running, retry, blocked)}
        end

      _ ->
        {:error, :issue_not_found}
    end
  end

  @spec refresh_payload(GenServer.name()) :: {:ok, map()} | {:error, :unavailable}
  def refresh_payload(orchestrator) do
    case Orchestrator.request_refresh(orchestrator) do
      :unavailable ->
        {:error, :unavailable}

      payload ->
        {:ok, Map.update!(payload, :requested_at, &DateTime.to_iso8601/1)}
    end
  end

  defp issue_payload_body(issue_identifier, running, retry, blocked) do
    %{
      issue_identifier: issue_identifier,
      issue_id: issue_id_from_entries(running, retry, blocked),
      status: issue_status(running, retry, blocked),
      workspace: %{
        path: workspace_path(issue_identifier, running, retry, blocked),
        host: workspace_host(running, retry, blocked),
        artifacts: public_workspace_artifacts(workspace_artifacts(running, retry, blocked))
      },
      attempts: %{
        restart_count: restart_count(retry),
        current_retry_attempt: retry_attempt(retry)
      },
      running: running && running_issue_payload(running),
      retry: retry && retry_issue_payload(retry),
      blocked: blocked && blocked_issue_payload(blocked),
      work_efficiency: issue_work_efficiency(running, retry, blocked),
      logs: %{
        codex_session_logs: []
      },
      recent_events: recent_events_payload(running || blocked),
      last_error: (blocked && blocked.error) || (retry && retry.error),
      tracked: %{}
    }
  end

  defp issue_id_from_entries(running, retry, blocked),
    do: (running && running.issue_id) || (retry && retry.issue_id) || (blocked && blocked.issue_id)

  defp enrich_snapshot(snapshot) do
    running = Enum.map(snapshot.running, &enrich_entry_artifacts/1)
    retrying = Enum.map(snapshot.retrying, &enrich_entry_artifacts/1)
    blocked = Enum.map(Map.get(snapshot, :blocked, []), &enrich_entry_artifacts/1)
    artifact_totals = workspace_artifact_totals(running, retrying, blocked)
    total_tokens = get_in(snapshot, [:codex_totals, :total_tokens])

    %{
      snapshot
      | running: running,
        retrying: retrying,
        blocked: blocked,
        work_efficiency: WorkEfficiency.aggregate(Map.get(snapshot, :work_efficiency), total_tokens, artifact_totals)
    }
  end

  defp enrich_entry_artifacts(entry) when is_map(entry) do
    artifacts =
      Map.get(entry, :workspace_artifacts) ||
        maybe_probe_workspace_artifacts(entry)

    Map.put(entry, :workspace_artifacts, artifacts)
  end

  defp maybe_probe_workspace_artifacts(entry) do
    case Map.get(entry, :workspace_path) do
      path when is_binary(path) and path != "" ->
        WorkspaceArtifacts.cached_probe(path, Map.get(entry, :worker_host))

      _ ->
        nil
    end
  end

  defp workspace_artifact_totals(running, retrying, blocked) do
    Enum.reduce(running ++ retrying ++ blocked, WorkspaceArtifacts.empty(), fn entry, acc ->
      artifacts = Map.get(entry, :workspace_artifacts) || %{}

      %{
        acc
        | reviewable_untracked_count: Map.get(acc, :reviewable_untracked_count, 0) + Map.get(artifacts, :reviewable_untracked_count, 0),
          generated_untracked_count: Map.get(acc, :generated_untracked_count, 0) + Map.get(artifacts, :generated_untracked_count, 0)
      }
    end)
  end

  defp issue_work_efficiency(running, retry, blocked), do: WorkEfficiency.entry(running || retry || blocked)

  defp restart_count(retry), do: max(retry_attempt(retry) - 1, 0)
  defp retry_attempt(nil), do: 0
  defp retry_attempt(retry), do: retry.attempt || 0

  defp issue_status(running, _retry, _blocked) when not is_nil(running), do: "running"
  defp issue_status(nil, retry, _blocked) when not is_nil(retry), do: "retrying"
  defp issue_status(nil, nil, _blocked), do: "blocked"

  defp running_entry_payload(entry) do
    %{
      issue_id: entry.issue_id,
      issue_identifier: entry.identifier,
      issue_url: Map.get(entry, :issue_url),
      state: entry.state,
      lifecycle: Map.get(entry, :lifecycle),
      worker_host: Map.get(entry, :worker_host),
      workspace_path: Map.get(entry, :workspace_path),
      workspace_artifacts: public_workspace_artifacts(Map.get(entry, :workspace_artifacts)),
      session_id: entry.session_id,
      turn_count: Map.get(entry, :turn_count, 0),
      last_event: entry.last_codex_event,
      last_message: summarize_message(entry.last_codex_message),
      started_at: iso8601(entry.started_at),
      last_event_at: iso8601(entry.last_codex_timestamp),
      tokens: %{
        input_tokens: entry.codex_input_tokens,
        output_tokens: entry.codex_output_tokens,
        total_tokens: entry.codex_total_tokens
      }
    }
  end

  defp retry_entry_payload(entry) do
    %{
      issue_id: entry.issue_id,
      issue_identifier: entry.identifier,
      issue_url: Map.get(entry, :issue_url),
      attempt: entry.attempt,
      due_at: due_at_iso8601(entry.due_in_ms),
      error: entry.error,
      worker_host: Map.get(entry, :worker_host),
      workspace_path: Map.get(entry, :workspace_path),
      workspace_artifacts: public_workspace_artifacts(Map.get(entry, :workspace_artifacts))
    }
  end

  defp blocked_entry_payload(entry) do
    %{
      issue_id: entry.issue_id,
      issue_identifier: entry.identifier,
      issue_url: blocked_issue_url(entry),
      state: blocked_issue_state(entry),
      error: entry.error,
      worker_host: Map.get(entry, :worker_host),
      workspace_path: Map.get(entry, :workspace_path),
      workspace_artifacts: public_workspace_artifacts(Map.get(entry, :workspace_artifacts)),
      session_id: entry.session_id,
      blocked_at: iso8601(entry.blocked_at),
      last_event: entry.last_codex_event,
      last_message: summarize_message(entry.last_codex_message),
      last_event_at: iso8601(entry.last_codex_timestamp)
    }
  end

  defp running_issue_payload(running) do
    %{
      worker_host: Map.get(running, :worker_host),
      workspace_path: Map.get(running, :workspace_path),
      workspace_artifacts: public_workspace_artifacts(Map.get(running, :workspace_artifacts)),
      lifecycle: Map.get(running, :lifecycle),
      session_id: running.session_id,
      turn_count: Map.get(running, :turn_count, 0),
      state: running.state,
      started_at: iso8601(running.started_at),
      last_event: running.last_codex_event,
      last_message: summarize_message(running.last_codex_message),
      last_event_at: iso8601(running.last_codex_timestamp),
      tokens: %{
        input_tokens: running.codex_input_tokens,
        output_tokens: running.codex_output_tokens,
        total_tokens: running.codex_total_tokens
      }
    }
  end

  defp retry_issue_payload(retry) do
    %{
      attempt: retry.attempt,
      due_at: due_at_iso8601(retry.due_in_ms),
      error: retry.error,
      worker_host: Map.get(retry, :worker_host),
      workspace_path: Map.get(retry, :workspace_path),
      workspace_artifacts: public_workspace_artifacts(Map.get(retry, :workspace_artifacts))
    }
  end

  defp blocked_issue_payload(blocked) do
    %{
      worker_host: Map.get(blocked, :worker_host),
      workspace_path: Map.get(blocked, :workspace_path),
      workspace_artifacts: public_workspace_artifacts(Map.get(blocked, :workspace_artifacts)),
      session_id: blocked.session_id,
      state: blocked_issue_state(blocked),
      error: blocked.error,
      blocked_at: iso8601(blocked.blocked_at),
      last_event: blocked.last_codex_event,
      last_message: summarize_message(blocked.last_codex_message),
      last_event_at: iso8601(blocked.last_codex_timestamp)
    }
  end

  defp workspace_path(issue_identifier, running, retry, blocked) do
    (running && Map.get(running, :workspace_path)) ||
      (retry && Map.get(retry, :workspace_path)) ||
      (blocked && Map.get(blocked, :workspace_path)) ||
      Path.join(Config.settings!().workspace.root, issue_identifier)
  end

  defp workspace_host(running, retry, blocked) do
    (running && Map.get(running, :worker_host)) ||
      (retry && Map.get(retry, :worker_host)) ||
      (blocked && Map.get(blocked, :worker_host))
  end

  defp workspace_artifacts(running, retry, blocked) do
    (running && Map.get(running, :workspace_artifacts)) ||
      (retry && Map.get(retry, :workspace_artifacts)) ||
      (blocked && Map.get(blocked, :workspace_artifacts))
  end

  defp public_workspace_artifacts(nil), do: nil

  defp public_workspace_artifacts(artifacts) when is_map(artifacts) do
    %{
      reviewable_untracked_count: Map.get(artifacts, :reviewable_untracked_count, 0),
      reviewable_untracked_summary: Map.get(artifacts, :reviewable_untracked_summary, []),
      generated_untracked_count: Map.get(artifacts, :generated_untracked_count, 0),
      generated_untracked_summary: Map.get(artifacts, :generated_untracked_summary, []),
      ignored_untracked_count: Map.get(artifacts, :ignored_untracked_count, 0),
      probe_error: Map.get(artifacts, :probe_error)
    }
  end

  defp blocked_issue_state(%{state: state}) when is_binary(state), do: state
  defp blocked_issue_state(%{state: state}) when is_atom(state), do: state
  defp blocked_issue_state(%{issue: %{state: state}}), do: state
  defp blocked_issue_state(_blocked), do: nil

  defp blocked_issue_url(%{issue_url: issue_url}) when is_binary(issue_url), do: issue_url
  defp blocked_issue_url(%{issue: %{url: issue_url}}), do: issue_url
  defp blocked_issue_url(_blocked), do: nil

  defp recent_events_payload(nil), do: []

  defp recent_events_payload(entry) do
    [
      %{
        at: iso8601(entry.last_codex_timestamp),
        event: entry.last_codex_event,
        message: summarize_message(entry.last_codex_message)
      }
    ]
    |> Enum.reject(&is_nil(&1.at))
  end

  defp summarize_message(nil), do: nil
  defp summarize_message(message), do: StatusDashboard.humanize_codex_message(message)

  defp due_at_iso8601(due_in_ms) when is_integer(due_in_ms) do
    DateTime.utc_now()
    |> DateTime.add(div(due_in_ms, 1_000), :second)
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp due_at_iso8601(_due_in_ms), do: nil

  defp iso8601(%DateTime{} = datetime) do
    datetime
    |> DateTime.truncate(:second)
    |> DateTime.to_iso8601()
  end

  defp iso8601(_datetime), do: nil
end
