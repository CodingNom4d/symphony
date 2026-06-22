defmodule SymphonyElixir.WorkEfficiencyTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.WorkEfficiency

  test "aggregate normalizes counters and token totals" do
    assert WorkEfficiency.aggregate(
             %{
               completed_diff_lines: 6,
               productive_turns: 2,
               unproductive_turns: "ignored"
             },
             12,
             %{reviewable_untracked_count: 3, generated_untracked_count: 4}
           ) == %{
             heuristic: WorkEfficiency.heuristic(),
             completed_diff_lines: 6,
             reviewable_untracked_count: 3,
             generated_untracked_count: 4,
             productive_turns: 2,
             unproductive_turns: 0,
             total_tokens: 12,
             diff_lines_per_1k_tokens: 500.0
           }
  end

  test "aggregate handles nil totals and non-positive token denominators" do
    assert WorkEfficiency.aggregate(nil, nil) == %{
             heuristic: WorkEfficiency.heuristic(),
             completed_diff_lines: 0,
             reviewable_untracked_count: 0,
             generated_untracked_count: 0,
             productive_turns: 0,
             unproductive_turns: 0,
             total_tokens: 0,
             diff_lines_per_1k_tokens: 0.0
           }

    assert WorkEfficiency.aggregate(%{completed_diff_lines: -1, productive_turns: -1, unproductive_turns: -1}, -10) ==
             %{
               heuristic: WorkEfficiency.heuristic(),
               completed_diff_lines: -1,
               reviewable_untracked_count: 0,
               generated_untracked_count: 0,
               productive_turns: -1,
               unproductive_turns: -1,
               total_tokens: 0,
               diff_lines_per_1k_tokens: 0.0
             }
  end

  test "entry returns nil for absent issue data and aggregates issue counters" do
    assert WorkEfficiency.entry(nil) == nil

    assert WorkEfficiency.entry(%{
             completed_diff_lines: 3,
             productive_turns: 1,
             codex_total_tokens: 6,
             workspace_artifacts: %{reviewable_untracked_count: 2, generated_untracked_count: 1}
           }) == %{
             heuristic: WorkEfficiency.heuristic(),
             completed_diff_lines: 3,
             reviewable_untracked_count: 2,
             generated_untracked_count: 1,
             productive_turns: 1,
             unproductive_turns: 0,
             total_tokens: 6,
             diff_lines_per_1k_tokens: 500.0
           }
  end

  test "empty totals contains the durable counter keys" do
    assert WorkEfficiency.empty_totals() == %{
             completed_diff_lines: 0,
             reviewable_untracked_count: 0,
             generated_untracked_count: 0,
             productive_turns: 0,
             unproductive_turns: 0
           }
  end
end
