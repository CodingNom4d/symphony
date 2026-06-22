defmodule Mix.Tasks.Guardrails.Check do
  use Mix.Task

  alias SymphonyElixir.BoundaryGuardrails

  @moduledoc """
  Enforces the dry-run/public-data boundary for TradingView-adjacent code paths.
  """
  @shortdoc "Fails when dry-run boundary guardrails are violated"

  @switches [project_root: :string]

  @impl Mix.Task
  def run(args) do
    {opts, _argv, _invalid} = OptionParser.parse(args, strict: @switches)

    project_root =
      opts
      |> Keyword.get(:project_root, File.cwd!())
      |> Path.expand()

    findings = BoundaryGuardrails.findings(project_root)

    if findings == [] do
      Mix.shell().info("guardrails.check: dry-run boundary rules passed")
      :ok
    else
      Enum.each(findings, fn finding ->
        Mix.shell().error("#{finding.path}:#{finding.line} #{finding.message} (#{finding.snippet})")
      end)

      Mix.raise("guardrails.check failed with #{length(findings)} finding(s)")
    end
  end
end
