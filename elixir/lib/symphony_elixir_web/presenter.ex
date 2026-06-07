defmodule SymphonyElixirWeb.Presenter do
  @moduledoc """
  Shared projections for the observability API and dashboard.
  """

  alias SymphonyElixir.{Config, Orchestrator, StatusDashboard}

  @spec state_payload(GenServer.name(), timeout()) :: map()
  def state_payload(orchestrator, snapshot_timeout_ms) do
    generated_at = DateTime.utc_now() |> DateTime.truncate(:second) |> DateTime.to_iso8601()

    case Orchestrator.snapshot(orchestrator, snapshot_timeout_ms) do
      %{} = snapshot ->
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
        host: workspace_host(running, retry, blocked)
      },
      attempts: %{
        restart_count: restart_count(retry),
        current_retry_attempt: retry_attempt(retry)
      },
      running: running && running_issue_payload(running),
      retry: retry && retry_issue_payload(retry),
      blocked: blocked && blocked_issue_payload(blocked),
      logs: %{
        codex_session_logs: transcript_payload(running || blocked)
      },
      recent_events: recent_events_payload(running || blocked),
      last_error: (blocked && blocked.error) || (retry && retry.error),
      tracked: %{}
    }
  end

  defp issue_id_from_entries(running, retry, blocked),
    do: (running && running.issue_id) || (retry && retry.issue_id) || (blocked && blocked.issue_id)

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
      worker_host: Map.get(entry, :worker_host),
      workspace_path: Map.get(entry, :workspace_path),
      session_id: entry.session_id,
      turn_count: Map.get(entry, :turn_count, 0),
      last_event: entry.last_codex_event,
      last_message: summarize_message(entry.last_codex_message),
      started_at: iso8601(entry.started_at),
      last_event_at: iso8601(entry.last_codex_timestamp),
      transcript: transcript_payload(entry),
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
      workspace_path: Map.get(entry, :workspace_path)
    }
  end

  defp blocked_entry_payload(entry) do
    %{
      issue_id: entry.issue_id,
      issue_identifier: entry.identifier,
      issue_url: Map.get(entry, :issue_url),
      state: entry.state,
      error: entry.error,
      worker_host: Map.get(entry, :worker_host),
      workspace_path: Map.get(entry, :workspace_path),
      session_id: entry.session_id,
      blocked_at: iso8601(entry.blocked_at),
      last_event: entry.last_codex_event,
      last_message: summarize_message(entry.last_codex_message),
      last_event_at: iso8601(entry.last_codex_timestamp),
      transcript: transcript_payload(entry)
    }
  end

  defp running_issue_payload(running) do
    %{
      worker_host: Map.get(running, :worker_host),
      workspace_path: Map.get(running, :workspace_path),
      session_id: running.session_id,
      turn_count: Map.get(running, :turn_count, 0),
      state: running.state,
      started_at: iso8601(running.started_at),
      last_event: running.last_codex_event,
      last_message: summarize_message(running.last_codex_message),
      last_event_at: iso8601(running.last_codex_timestamp),
      transcript: transcript_payload(running),
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
      workspace_path: Map.get(retry, :workspace_path)
    }
  end

  defp blocked_issue_payload(blocked) do
    %{
      worker_host: Map.get(blocked, :worker_host),
      workspace_path: Map.get(blocked, :workspace_path),
      session_id: blocked.session_id,
      state: blocked.state,
      error: blocked.error,
      blocked_at: iso8601(blocked.blocked_at),
      last_event: blocked.last_codex_event,
      last_message: summarize_message(blocked.last_codex_message),
      last_event_at: iso8601(blocked.last_codex_timestamp),
      transcript: transcript_payload(blocked)
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

  defp recent_events_payload(nil), do: []

  defp recent_events_payload(entry) do
    case transcript_payload(entry) do
      [] ->
        [
          %{
            at: iso8601(entry.last_codex_timestamp),
            event: entry.last_codex_event,
            message: summarize_message(entry.last_codex_message)
          }
        ]
        |> Enum.reject(&is_nil(&1.at))

      transcript ->
        Enum.map(transcript, fn item ->
          %{
            at: item.at,
            event: item.event,
            message: item.summary
          }
        end)
    end
  end

  defp transcript_payload(nil), do: []

  defp transcript_payload(entry) do
    entry
    |> Map.get(:codex_transcript, [])
    |> Enum.map(&transcript_entry_payload/1)
    |> merge_streaming_transcript_entries()
  end

  defp transcript_entry_payload(entry) when is_map(entry) do
    message = Map.get(entry, :message) || Map.get(entry, "message")
    event = Map.get(entry, :event) || Map.get(entry, "event")

    %{
      at: iso8601(Map.get(entry, :timestamp) || Map.get(entry, "timestamp")),
      event: event,
      role: transcript_role(event, message),
      summary: summarize_message(message),
      stream_delta: transcript_agent_stream_delta(message)
    }
  end

  defp transcript_entry_payload(entry) do
    %{
      at: nil,
      event: nil,
      role: "system",
      summary: summarize_message(entry),
      stream_delta: nil
    }
  end

  defp merge_streaming_transcript_entries(entries) do
    {entries, pending} =
      Enum.reduce(entries, {[], nil}, fn entry, {acc, pending} ->
        case Map.get(entry, :stream_delta) do
          delta when is_binary(delta) ->
            {acc, append_stream_delta(pending, entry, delta)}

          _other ->
            acc = flush_stream_delta(acc, pending)
            {[Map.drop(entry, [:stream_delta]) | acc], nil}
        end
      end)

    entries
    |> flush_stream_delta(pending)
    |> Enum.reverse()
  end

  defp append_stream_delta(nil, entry, delta) do
    %{
      at: entry.at,
      event: "agent_message",
      role: "agent",
      summary: delta
    }
  end

  defp append_stream_delta(pending, _entry, delta) do
    Map.update!(pending, :summary, &(&1 <> delta))
  end

  defp flush_stream_delta(entries, nil), do: entries
  defp flush_stream_delta(entries, pending), do: [pending | entries]

  defp transcript_role(_event, message) do
    method = transcript_message_method(message)

    cond do
      is_binary(method) and String.contains?(method, "user_message") -> "user"
      agent_message_method?(method) -> "agent"
      true -> "system"
    end
  end

  defp transcript_message_method(message) when is_map(message) do
    payload = Map.get(message, :message) || Map.get(message, "message") || message

    map_path(payload, [:payload, "method"]) ||
      map_path(payload, [:payload, :method]) ||
      map_path(payload, ["payload", "method"]) ||
      map_path(payload, ["payload", :method]) ||
      Map.get(payload, "method") ||
      Map.get(payload, :method)
  end

  defp transcript_message_method(_message), do: nil

  defp transcript_agent_stream_delta(message) when is_map(message) do
    method = transcript_message_method(message)

    if agent_message_method?(method) and String.contains?(method, "delta") do
      message
      |> transcript_message_payload()
      |> transcript_delta_content()
    end
  end

  defp transcript_agent_stream_delta(_message), do: nil

  defp agent_message_method?(method) when is_binary(method) do
    String.contains?(method, "agent_message") or String.contains?(method, "agentMessage")
  end

  defp agent_message_method?(_method), do: false

  defp transcript_message_payload(message) when is_map(message) do
    Map.get(message, :message) || Map.get(message, "message") || message
  end

  defp transcript_delta_content(payload) do
    map_path(payload, ["params", "msg", "content"]) ||
      map_path(payload, [:params, :msg, :content]) ||
      map_path(payload, ["params", "msg", "delta"]) ||
      map_path(payload, [:params, :msg, :delta]) ||
      map_path(payload, ["params", "msg", "text"]) ||
      map_path(payload, [:params, :msg, :text]) ||
      map_path(payload, ["params", "content"]) ||
      map_path(payload, [:params, :content]) ||
      map_path(payload, ["params", "delta"]) ||
      map_path(payload, [:params, :delta]) ||
      map_path(payload, ["params", "text"]) ||
      map_path(payload, [:params, :text])
  end

  defp map_path(payload, path) when is_map(payload) and is_list(path) do
    Enum.reduce_while(path, payload, fn key, acc ->
      if is_map(acc) and Map.has_key?(acc, key) do
        {:cont, Map.get(acc, key)}
      else
        {:halt, nil}
      end
    end)
  end

  defp map_path(_payload, _path), do: nil

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
