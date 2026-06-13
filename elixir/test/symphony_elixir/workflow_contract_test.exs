defmodule SymphonyElixir.WorkflowContractTest do
  use SymphonyElixir.TestSupport

  alias SymphonyElixir.Workflow
  alias SymphonyElixir.WorkflowContract

  @contract_cases [
    {:dox_before_workflow, "Instructions", "Before planning, reviewing, opening/updating the workpad, analyzing repo files, or editing files"},
    {:dox_agents_chain, "Instructions", "read every applicable child `AGENTS.md`"},
    {:dox_missing_root_fallback, "Instructions", "continue with any path-local `AGENTS.md` files"},
    {:dox_closeout, "Instructions", "closeout docs pass after meaningful edits"},
    {:memory_recall_only, "Instructions", "semantic memory only for recall and discovery"},
    {:memory_scope, "Instructions", "explicitly relevant local Codex skills or rules"},
    {:memory_workspace_authority, "Instructions", "Binding instructions must come from files in the current workspace"},
    {:memory_publish_reverified_or_requested, "Instructions", "unless it has been re-verified against current workspace files"},
    {:memory_provenance, "Instructions", "memory provenance: <source class> -> <verified workspace file>"},
    {:memory_no_private_copy, "Instructions", "do not copy private recalled content"},
    {:linear_tool_prerequisite, "Prerequisite: Linear MCP or `linear_graphql` tool is available", "If none are present"},
    {:linear_final_message_exit, "Prerequisite: Linear MCP or `linear_graphql` tool is available", "Report `blocked: missing Linear tool/auth` in the final message and exit"},
    {:linear_no_issue_workpad_mutations, "Blocked-access escape hatch (required behavior)", "do not attempt issue state changes, workpad updates"},
    {:linear_no_blocker_comments, "Blocked-access escape hatch (required behavior)", "or blocker comments"},
    {:related_skills_no_human_wait, "Related skills", "do not wait indefinitely for human input"},
    {:app_runtime_preferred_tools, "App runtime validation (required)", "Prefer `launch-app`"},
    {:app_runtime_substitute, "App runtime validation (required)", "documented manual runtime check"},
    {:app_runtime_substitute_evidence, "App runtime validation (required)", "record that substitute evidence in the workpad"},
    {:app_runtime_no_overclaim, "App runtime validation (required)", "Do not search indefinitely or claim app validation without evidence"},
    {:app_runtime_blocked_access, "App runtime validation (required)", "If no runtime substitute exists and app-touching validation is required"}
  ]

  test "current workflow prompt satisfies unattended agent contracts" do
    assert :ok = WorkflowContract.validate_prompt(current_prompt!())
  end

  test "missing Linear no-mutation final-exit contract returns useful errors" do
    prompt = """
    ## Prerequisite: Linear MCP or `linear_graphql` tool is available

    The agent should be able to talk to Linear. If none are present, move the ticket to `Human Review`
    with a short blocker brief in the workpad.
    """

    assert {:error, errors} = WorkflowContract.validate_prompt(prompt)
    assert_error(errors, :linear_final_message_exit, "Prerequisite: Linear MCP or `linear_graphql` tool is available")
    assert_error(errors, :linear_no_issue_workpad_mutations, "Blocked-access escape hatch (required behavior)")
  end

  test "validation is section-scoped and ignores snippets in the wrong section" do
    prompt =
      current_prompt!()
      |> remove_from_section("Instructions", "apply the DOX workflow")
      |> Kernel.<>("""

      ## Contradictory example

      This example says to apply the DOX workflow, but it is not the binding Instructions section.
      """)

    assert {:error, errors} = WorkflowContract.validate_prompt(prompt)
    assert_error(errors, :dox_before_workflow, "Instructions", "apply the DOX workflow")
  end

  test "missing contract snippets return actionable section and snippet details" do
    for {id, section, snippet} <- @contract_cases do
      prompt = remove_from_section(current_prompt!(), section, snippet)

      assert {:error, errors} = WorkflowContract.validate_prompt(prompt)
      assert_error(errors, id, section, snippet)
    end
  end

  defp assert_error(errors, id, section) do
    assert Enum.any?(errors, fn error -> contract_error?(error, id, section) end),
           "expected #{inspect(id)} in #{inspect(section)}, got #{inspect(errors)}"
  end

  defp assert_error(errors, id, section, snippet) do
    assert Enum.any?(errors, fn error -> contract_error?(error, id, section, snippet) end),
           "expected #{inspect(id)} missing #{inspect(snippet)} in #{inspect(section)}, got #{inspect(errors)}"
  end

  defp contract_error?(%{id: id, section: section}, id, section), do: true
  defp contract_error?(_error, _id, _section), do: false

  defp contract_error?(%{id: id, section: section, missing: missing}, id, section, snippet) do
    snippet in missing
  end

  defp contract_error?(_error, _id, _section, _snippet), do: false

  defp remove_from_section(prompt, section, snippet) do
    section_header = section_header(section)
    {before_section, rest} = split_once!(prompt, section_header)
    {section_body, after_section} = split_section_body(rest)

    before_section <> section_header <> String.replace(section_body, snippet, "", global: false) <> after_section
  end

  defp split_section_body(rest) do
    case :binary.match(rest, "\n## ") do
      {index, _length} -> String.split_at(rest, index)
      :nomatch -> {rest, ""}
    end
  end

  defp split_once!(text, marker) do
    case String.split(text, marker, parts: 2) do
      [before_marker, after_marker] -> {before_marker, after_marker}
    end
  end

  defp section_header("Instructions"), do: "Instructions:"
  defp section_header(section), do: "## #{section}"

  defp current_prompt! do
    original_workflow_path = Workflow.workflow_file_path()
    on_exit(fn -> Workflow.set_workflow_file_path(original_workflow_path) end)
    Workflow.clear_workflow_file_path()

    assert {:ok, %{prompt: prompt}} = Workflow.load()
    prompt
  end
end
