defmodule SymphonyElixir.WorkflowContract do
  @moduledoc """
  Validates durable contracts embedded in the unattended workflow prompt.
  """

  @type error_id ::
          :dox_before_workflow
          | :dox_agents_chain
          | :dox_missing_root_fallback
          | :dox_closeout
          | :memory_recall_only
          | :memory_scope
          | :memory_workspace_authority
          | :memory_publish_reverified_or_requested
          | :memory_provenance
          | :memory_no_private_copy
          | :linear_tool_prerequisite
          | :linear_final_message_exit
          | :linear_no_issue_workpad_mutations
          | :linear_no_blocker_comments
          | :related_skills_no_human_wait
          | :app_runtime_preferred_tools
          | :app_runtime_substitute
          | :app_runtime_substitute_evidence
          | :app_runtime_no_overclaim
          | :app_runtime_blocked_access

  @type error :: %{
          id: error_id(),
          section: String.t(),
          missing: [String.t()]
        }

  @required_contracts [
    %{
      id: :dox_before_workflow,
      section: "Instructions",
      snippets: [
        "Before planning, reviewing, opening/updating the workpad, analyzing repo files, or editing files",
        "apply the DOX workflow"
      ]
    },
    %{
      id: :dox_agents_chain,
      section: "Instructions",
      snippets: [
        "read the repository root `AGENTS.md`",
        "read every applicable child `AGENTS.md`",
        "nearest local contract plus parent contracts"
      ]
    },
    %{
      id: :dox_missing_root_fallback,
      section: "Instructions",
      snippets: [
        "If no root `AGENTS.md` exists",
        "continue with any path-local `AGENTS.md` files",
        "note the missing root only when relevant to the task"
      ]
    },
    %{id: :dox_closeout, section: "Instructions", snippets: ["closeout docs pass after meaningful edits"]},
    %{id: :memory_recall_only, section: "Instructions", snippets: ["semantic memory only for recall and discovery"]},
    %{
      id: :memory_scope,
      section: "Instructions",
      snippets: [
        "current repository, current issue",
        "explicitly relevant local Codex skills or rules"
      ]
    },
    %{
      id: :memory_workspace_authority,
      section: "Instructions",
      snippets: [
        "Binding instructions must come from files in the current workspace"
      ]
    },
    %{
      id: :memory_publish_reverified_or_requested,
      section: "Instructions",
      snippets: [
        "Do not publish recalled content into Linear, PRs, issues, or durable docs",
        "unless it has been re-verified against current workspace files",
        "or the user explicitly asks to use that recalled source"
      ]
    },
    %{
      id: :memory_provenance,
      section: "Instructions",
      snippets: [
        "record only provenance",
        "memory provenance: <source class> -> <verified workspace file>"
      ]
    },
    %{id: :memory_no_private_copy, section: "Instructions", snippets: ["do not copy private recalled content"]},
    %{
      id: :linear_tool_prerequisite,
      section: "Prerequisite: Linear MCP or `linear_graphql` tool is available",
      snippets: [
        "If none are present"
      ]
    },
    %{
      id: :linear_final_message_exit,
      section: "Prerequisite: Linear MCP or `linear_graphql` tool is available",
      snippets: [
        "Report `blocked: missing Linear tool/auth` in the final message and exit"
      ]
    },
    %{
      id: :linear_no_issue_workpad_mutations,
      section: "Blocked-access escape hatch (required behavior)",
      snippets: [
        "If Linear itself is unavailable",
        "do not attempt issue state changes, workpad updates"
      ]
    },
    %{
      id: :linear_no_blocker_comments,
      section: "Blocked-access escape hatch (required behavior)",
      snippets: [
        "If Linear itself is unavailable",
        "or blocker comments"
      ]
    },
    %{
      id: :related_skills_no_human_wait,
      section: "Related skills",
      snippets: [
        "Symphony unattended override",
        "do not wait indefinitely for human input"
      ]
    },
    %{
      id: :app_runtime_preferred_tools,
      section: "App runtime validation (required)",
      snippets: [
        "Prefer `launch-app`",
        "`github-pr-media`"
      ]
    },
    %{
      id: :app_runtime_substitute,
      section: "App runtime validation (required)",
      snippets: [
        "If either capability is unavailable",
        "repo-local validation command",
        "documented manual runtime check"
      ]
    },
    %{
      id: :app_runtime_substitute_evidence,
      section: "App runtime validation (required)",
      snippets: [
        "record that substitute evidence in the workpad"
      ]
    },
    %{
      id: :app_runtime_no_overclaim,
      section: "App runtime validation (required)",
      snippets: [
        "Do not search indefinitely or claim app validation without evidence"
      ]
    },
    %{
      id: :app_runtime_blocked_access,
      section: "App runtime validation (required)",
      snippets: [
        "If no runtime substitute exists and app-touching validation is required",
        "blocked-access escape hatch"
      ]
    }
  ]

  @spec validate_prompt(String.t()) :: :ok | {:error, [error()]}
  def validate_prompt(prompt) when is_binary(prompt) do
    errors =
      @required_contracts
      |> Enum.map(&validate_contract(prompt, &1))
      |> Enum.reject(&is_nil/1)

    case errors do
      [] -> :ok
      _ -> {:error, errors}
    end
  end

  defp validate_contract(prompt, contract) do
    section = section_text(prompt, contract.section)
    missing = Enum.reject(contract.snippets, &String.contains?(section, &1))

    case missing do
      [] -> nil
      _ -> %{id: contract.id, section: contract.section, missing: missing}
    end
  end

  defp section_text(prompt, section) do
    section_header = section_header(section)

    case String.split(prompt, section_header, parts: 2) do
      [_before_section, rest] ->
        rest
        |> split_next_section()
        |> elem(0)

      [_] ->
        ""
    end
  end

  defp split_next_section(rest) do
    case :binary.match(rest, "\n## ") do
      {index, _length} -> String.split_at(rest, index)
      :nomatch -> {rest, ""}
    end
  end

  defp section_header("Instructions"), do: "Instructions:"
  defp section_header(section), do: "## #{section}"
end
