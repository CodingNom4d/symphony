defmodule SymphonyElixir.WorkEfficiency do
  @moduledoc """
  Shared work-efficiency heuristic shaping for Symphony observability surfaces.
  """

  @heuristic "Completed diff lines per 1k tokens (efficiency heuristic only; not a quality score)"
  @empty_totals %{
    completed_diff_lines: 0,
    reviewable_untracked_count: 0,
    generated_untracked_count: 0,
    productive_turns: 0,
    unproductive_turns: 0
  }

  @spec heuristic() :: String.t()
  def heuristic, do: @heuristic

  @spec empty_totals() :: map()
  def empty_totals, do: @empty_totals

  @spec aggregate(map() | nil, integer() | nil, map() | nil) :: map()
  def aggregate(work_totals, total_tokens, artifact_totals \\ nil) do
    work_totals = work_totals || %{}
    artifact_totals = artifact_totals || %{}
    completed_diff_lines = count(work_totals, :completed_diff_lines)

    reviewable_untracked_count =
      count(work_totals, :reviewable_untracked_count) + count(artifact_totals, :reviewable_untracked_count)

    generated_untracked_count =
      count(work_totals, :generated_untracked_count) + count(artifact_totals, :generated_untracked_count)

    productive_turns = count(work_totals, :productive_turns)
    unproductive_turns = count(work_totals, :unproductive_turns)
    total_tokens = max(normalize_total_tokens(total_tokens), 0)

    %{
      heuristic: @heuristic,
      completed_diff_lines: completed_diff_lines,
      reviewable_untracked_count: reviewable_untracked_count,
      generated_untracked_count: generated_untracked_count,
      productive_turns: productive_turns,
      unproductive_turns: unproductive_turns,
      total_tokens: total_tokens,
      diff_lines_per_1k_tokens: diff_lines_per_1k_tokens(completed_diff_lines, total_tokens)
    }
  end

  @spec entry(map() | nil) :: map() | nil
  def entry(nil), do: nil

  def entry(entry) when is_map(entry) do
    aggregate(entry, Map.get(entry, :codex_total_tokens), Map.get(entry, :workspace_artifacts))
  end

  defp diff_lines_per_1k_tokens(_completed_diff_lines, total_tokens) when total_tokens <= 0, do: 0.0

  defp diff_lines_per_1k_tokens(completed_diff_lines, total_tokens) do
    completed_diff_lines * 1000.0 / total_tokens
  end

  defp normalize_total_tokens(total_tokens) when is_integer(total_tokens), do: total_tokens
  defp normalize_total_tokens(_total_tokens), do: 0

  defp count(map, key) do
    case Map.get(map, key, 0) do
      value when is_integer(value) and value > 0 -> value
      value when is_integer(value) -> value
      _ -> 0
    end
  end
end
