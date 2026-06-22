defmodule SymphonyElixir.WorkspaceArtifactsTest do
  use ExUnit.Case, async: true

  alias SymphonyElixir.WorkspaceArtifacts

  test "probe classifies tracked-only workspaces without counting untracked artifacts" do
    repo = make_repo!("tracked-only")
    write_file!(repo, "tracked.txt", "updated tracked content\n")

    assert WorkspaceArtifacts.probe(repo) == %{
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
  end

  test "probe counts reviewable untracked files" do
    repo = make_repo!("untracked-only")
    write_file!(repo, "notes.md", "# Notes\n")

    assert WorkspaceArtifacts.probe(repo) == %{
             reviewable_untracked_count: 1,
             reviewable_untracked_paths: ["notes.md"],
             reviewable_untracked_summary: ["notes.md"],
             generated_untracked_count: 0,
             generated_untracked_paths: [],
             generated_untracked_summary: [],
             ignored_untracked_count: 0,
             ignored_untracked_paths: [],
             ignored_untracked_summary: [],
             probe_error: nil
           }
  end

  test "probe excludes ignored and generated directories from reviewable counts" do
    repo = make_repo!("ignored-and-generated")
    write_file!(repo, ".gitignore", "ignored/\n")
    cmd!(repo, "git", ["add", ".gitignore"])
    cmd!(repo, "git", ["commit", "-m", "track gitignore"])
    write_file!(repo, "ignored/secret.txt", "ignore me\n")
    write_file!(repo, "tmp/scratch.txt", "generated temp\n")
    write_file!(repo, "node_modules/pkg/index.js", "console.log('cache')\n")
    write_file!(repo, "assets/node_modules/pkg/index.js", "console.log('asset cache')\n")
    write_file!(repo, "assets/build/app.js", "generated asset\n")
    write_file!(repo, "priv/static/app.js", "generated static\n")

    assert WorkspaceArtifacts.probe(repo) == %{
             reviewable_untracked_count: 0,
             reviewable_untracked_paths: [],
             reviewable_untracked_summary: [],
             generated_untracked_count: 5,
             generated_untracked_paths: [
               "assets/build/app.js",
               "assets/node_modules/pkg/index.js",
               "node_modules/pkg/index.js",
               "priv/static/app.js",
               "tmp/scratch.txt"
             ],
             generated_untracked_summary: [
               "assets/build/app.js",
               "assets/node_modules/pkg/index.js",
               "node_modules/pkg/index.js",
               "priv/static/app.js",
               "tmp/scratch.txt"
             ],
             ignored_untracked_count: 1,
             ignored_untracked_paths: ["ignored/"],
             ignored_untracked_summary: ["ignored/"],
             probe_error: nil
           }
  end

  test "probe reports mixed workspaces with separate reviewable and generated summaries" do
    repo = make_repo!("mixed")
    write_file!(repo, "tracked.txt", "updated tracked content\n")
    write_file!(repo, "docs/plan.md", "review me\n")
    write_file!(repo, "_build/output/app.beam", "generated\n")

    assert WorkspaceArtifacts.probe(repo) == %{
             reviewable_untracked_count: 1,
             reviewable_untracked_paths: ["docs/plan.md"],
             reviewable_untracked_summary: ["docs/plan.md"],
             generated_untracked_count: 1,
             generated_untracked_paths: ["_build/output/app.beam"],
             generated_untracked_summary: ["_build/output/app.beam"],
             ignored_untracked_count: 0,
             ignored_untracked_paths: [],
             ignored_untracked_summary: [],
             probe_error: nil
           }
  end

  test "probe returns empty for missing local paths and probes remote workspaces over ssh" do
    assert WorkspaceArtifacts.probe(nil) == WorkspaceArtifacts.empty()
    assert WorkspaceArtifacts.probe("") == WorkspaceArtifacts.empty()

    repo = make_repo!("remote")
    write_file!(repo, "docs/remote.md", "review me remotely\n")
    previous_path = System.get_env("PATH")

    on_exit(fn ->
      case previous_path do
        nil -> System.delete_env("PATH")
        value -> System.put_env("PATH", value)
      end
    end)

    fake_bin =
      Path.join(
        System.tmp_dir!(),
        "symphony-workspace-artifacts-ssh-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(fake_bin)
    fake_ssh = Path.join(fake_bin, "ssh")

    File.write!(fake_ssh, """
    #!/bin/sh
    last=""
    for arg in "$@"; do
      last="$arg"
    done
    eval "$last"
    """)

    File.chmod!(fake_ssh, 0o755)
    git_path = System.find_executable("git")
    assert is_binary(git_path)
    System.put_env("PATH", fake_bin <> ":" <> Path.dirname(git_path))

    assert WorkspaceArtifacts.probe(repo, "worker-01") == %{
             reviewable_untracked_count: 1,
             reviewable_untracked_paths: ["docs/remote.md"],
             reviewable_untracked_summary: ["docs/remote.md"],
             generated_untracked_count: 0,
             generated_untracked_paths: [],
             generated_untracked_summary: [],
             ignored_untracked_count: 0,
             ignored_untracked_paths: [],
             ignored_untracked_summary: [],
             probe_error: nil
           }
  end

  test "probe reports git-status failures for non-repositories and unreadable paths" do
    non_repo =
      Path.join(
        System.tmp_dir!(),
        "symphony-workspace-artifacts-non-repo-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.rm_rf!(non_repo)
    File.mkdir_p!(non_repo)

    assert WorkspaceArtifacts.probe(non_repo).probe_error =~ "git status failed with exit"
    assert WorkspaceArtifacts.probe(Path.join(non_repo, "missing")).probe_error =~ "git status failed"
  end

  test "probe reports missing git or ssh and probe timeouts" do
    repo = make_repo!("probe-errors")
    previous_path = System.get_env("PATH")

    on_exit(fn ->
      case previous_path do
        nil -> System.delete_env("PATH")
        value -> System.put_env("PATH", value)
      end
    end)

    System.put_env("PATH", "")
    assert WorkspaceArtifacts.probe(repo).probe_error == "git executable not available"
    assert WorkspaceArtifacts.probe(repo, "worker-01").probe_error == "ssh executable not available"

    fake_bin =
      Path.join(
        System.tmp_dir!(),
        "symphony-workspace-artifacts-bin-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(fake_bin)
    fake_git = Path.join(fake_bin, "git")
    File.write!(fake_git, "#!/bin/sh\nwhile true; do :; done\n")
    File.chmod!(fake_git, 0o755)

    System.put_env("PATH", fake_bin)
    assert WorkspaceArtifacts.probe(repo).probe_error == "workspace artifact probe failed: :probe_timeout"
  end

  test "cached_probe returns immediately with pending artifacts while refreshing in the background" do
    repo = make_repo!("cached-probe")
    previous_path = System.get_env("PATH")

    on_exit(fn ->
      case previous_path do
        nil -> System.delete_env("PATH")
        value -> System.put_env("PATH", value)
      end
    end)

    fake_bin =
      Path.join(
        System.tmp_dir!(),
        "symphony-workspace-artifacts-cache-bin-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.mkdir_p!(fake_bin)
    fake_git = Path.join(fake_bin, "git")
    File.write!(fake_git, "#!/bin/sh\nwhile true; do :; done\n")
    File.chmod!(fake_git, 0o755)

    System.put_env("PATH", fake_bin)

    started_at = System.monotonic_time(:millisecond)
    artifacts = WorkspaceArtifacts.cached_probe(repo)
    elapsed_ms = System.monotonic_time(:millisecond) - started_at

    assert elapsed_ms < 250
    assert artifacts.reviewable_untracked_count == 0
    assert artifacts.probe_error == "workspace artifact probe pending"
  end

  test "cached_probe refreshes stale cached artifacts in the background" do
    assert WorkspaceArtifacts.cached_probe(nil) == nil
    assert WorkspaceArtifacts.cached_probe("") == nil

    repo = make_repo!("stale-cache")
    key = {repo, nil}
    stale_artifacts = WorkspaceArtifacts.empty()

    WorkspaceArtifacts.cached_probe(repo)
    :ets.insert(:symphony_workspace_artifacts_cache, {key, stale_artifacts, System.monotonic_time(:millisecond) - 10_000, false})

    assert WorkspaceArtifacts.cached_probe(repo) == stale_artifacts
    assert [{^key, ^stale_artifacts, _refreshed_at_ms, true}] = :ets.lookup(:symphony_workspace_artifacts_cache, key)
  end

  defp make_repo!(name) do
    repo =
      Path.join(
        System.tmp_dir!(),
        "symphony-workspace-artifacts-#{name}-#{System.unique_integer([:positive, :monotonic])}"
      )

    File.rm_rf!(repo)
    File.mkdir_p!(repo)
    cmd!(repo, "git", ["init"])
    cmd!(repo, "git", ["config", "user.email", "symphony@example.test"])
    cmd!(repo, "git", ["config", "user.name", "Symphony Test"])
    write_file!(repo, "tracked.txt", "tracked content\n")
    cmd!(repo, "git", ["add", "tracked.txt"])
    cmd!(repo, "git", ["commit", "-m", "initial"])
    repo
  end

  defp write_file!(repo, path, contents) do
    full_path = Path.join(repo, path)
    File.mkdir_p!(Path.dirname(full_path))
    File.write!(full_path, contents)
  end

  defp cmd!(cwd, executable, args) do
    {output, 0} = System.cmd(executable, args, cd: cwd, stderr_to_stdout: true)
    output
  end
end
