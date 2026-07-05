defmodule CartographBackend.Steps.SafePath do
  @moduledoc """
  Confines file paths used by DSL steps to an allowed sandbox root.

  Step `path` params are attacker-controllable (any user who can author a job).
  Without confinement, `writeOutput`/`readDirectory` allow arbitrary file write
  and directory listing anywhere the BEAM process can reach.

  There are two sandbox scopes:

    * global (`project_id = nil`) — the whole data root; used by jobs that
      belong to no project and by the admin Files view.
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

  @doc """
  Resolves `path` to an absolute path and ensures it is inside the scope's
  sandbox. Returns `{:ok, absolute_path}` or `{:error, reason}`.

  Global scope keeps the historical behavior: the path is expanded against the
  cwd (job params conventionally start with `data/`). For a project scope the
  path is taken relative to the project sandbox — a leading `data/` is
  stripped, so the same DSL works whether the job is in a project or not.
  """
  def resolve(path, project_id \\ nil)

  def resolve(path, nil) when is_binary(path) do
    confine(Path.expand(path), root(), path)
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

  defp confine(full, base, original) do
    if full == base or String.starts_with?(full, base <> "/") do
      {:ok, full}
    else
      {:error, "Path '#{original}' is outside the allowed data directory"}
    end
  end
end
