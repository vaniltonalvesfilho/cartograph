defmodule CartographBackend.Steps.SafePath do
  @moduledoc """
  Confines file paths used by DSL steps to an allowed sandbox root.

  Step `path` params are attacker-controllable (any user who can author a job).
  Without confinement, `writeOutput`/`readDirectory` allow arbitrary file write
  and directory listing anywhere the BEAM process can reach.

  There are two sandbox scopes:

    * global (`project_id = nil`) — the data root *minus* `<root>/projects`;
      used by jobs that belong to no project. It is deliberately not a superset
      of the project sandboxes: a global job cannot read or write another
      project's files.
    * per project — `<root>/projects/<id>`; a job that belongs to a project is
      confined there and cannot see other projects' files nor the global dirs.
  """

  @doc "Absolute path of the sandbox root (defaults to `<cwd>/data`)."
  def root do
    :cartograph_backend
    |> Application.get_env(:step_data_root, "data")
    |> Path.expand()
  end

  @doc "Absolute sandbox root for a scope: the data root, or the project's dir."
  def sandbox_root(nil), do: root()

  def sandbox_root(project_id) when is_integer(project_id),
    do: Path.join([root(), "projects", Integer.to_string(project_id)])

  @doc "Absolute path of the directory holding every project sandbox."
  def projects_root, do: Path.join(root(), "projects")

  @doc """
  Resolves `path` to an absolute path and ensures it is inside the scope's
  sandbox. Returns `{:ok, absolute_path}` or `{:error, reason}`.

  Global scope keeps the historical behavior: the path is expanded against the
  cwd (job params conventionally start with `data/`), except that the
  per-project sandboxes under `<root>/projects` are off limits. For a project
  scope the path is taken relative to the project sandbox — a leading `data/`
  is stripped, so the same DSL works whether the job is in a project or not.
  """
  def resolve(path, project_id \\ nil)

  def resolve(path, nil) when is_binary(path) do
    with {:ok, full} <- confine(Path.expand(path), root(), path) do
      reject_projects_subtree(full, path)
    end
  end

  def resolve(path, project_id) when is_binary(path) and is_integer(project_id) do
    base = sandbox_root(project_id)

    full =
      case path do
        # Absolute paths reach steps via state (readDirectory stores absolute
        # file paths); they pass only if already inside this sandbox.
        "/" <> _ -> Path.expand(path)
        "data" -> base
        _ -> Path.expand(Path.join(base, String.replace_prefix(path, "data/", "")))
      end

    confine(full, base, path)
  end

  def resolve(_, _), do: {:error, "Invalid path"}

  # Keeps the global scope from being a superset of every project sandbox.
  defp reject_projects_subtree(full, original) do
    base = projects_root()

    if under?(canonical(full), canonical(base)) do
      {:error, "Path '#{original}' belongs to a project sandbox"}
    else
      {:ok, full}
    end
  end

  defp confine(full, base, original) do
    if under?(canonical(full), canonical(base)) do
      {:ok, full}
    else
      {:error, "Path '#{original}' is outside the allowed data directory"}
    end
  end

  defp under?(full, base), do: full == base or String.starts_with?(full, base <> "/")

  # ── Symlink resolution ───────────────────────────────────────────────────────

  @doc """
  Expands `path` and follows any symlink along the way.

  `Path.expand/1` is pure string arithmetic: it collapses `..` but knows
  nothing about the filesystem, so a symlink placed inside the sandbox — by an
  archive that carries one, or by anything else with write access to the data
  directory — resolves to a path that still *looks* confined while pointing
  anywhere. Confinement is checked against this canonical form instead.

  Components that do not exist yet are kept as-is, since steps legitimately
  write files that are not there.
  """
  def canonical(path), do: canonical(path, 0)

  # A symlink chain this long is a loop or an attack; treat the path as-is and
  # let the confinement check reject it.
  defp canonical(path, depth) when depth > 16, do: Path.expand(path)

  defp canonical(path, depth) do
    path
    |> Path.expand()
    |> Path.split()
    |> Enum.reduce("/", fn segment, acc ->
      candidate = Path.join(acc, segment)

      case :file.read_link(candidate) do
        {:ok, target} ->
          target = to_string(target)

          resolved =
            if Path.type(target) == :absolute,
              do: target,
              else: Path.join(acc, target)

          canonical(resolved, depth + 1)

        # Not a link, or does not exist yet.
        {:error, _} ->
          candidate
      end
    end)
  end
end
