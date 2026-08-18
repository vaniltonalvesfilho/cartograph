defmodule CartographBackend.Files do
  @moduledoc """
  Manages a project's data sandbox (`Steps.SafePath.sandbox_root/1`) for the
  dashboard's per-project Files area: list a directory, store an upload,
  resolve a download, create folders and delete entries.

  Every function is scoped to a single project: paths from the client are
  RELATIVE to that project's sandbox (`<data root>/projects/<id>`) and are
  re-confined there, so `../`/absolute escapes fail the same way they do for
  the project's DSL steps, and one project can never reach another's files.
  """

  alias CartographBackend.Steps.SafePath

  @type entry :: %{
          name: String.t(),
          isDir: boolean(),
          size: non_neg_integer() | nil,
          modifiedAt: DateTime.t() | nil
        }

  @doc "Lists a directory (path relative to the project sandbox, \"\" = root)."
  @spec list(integer(), String.t()) :: {:ok, [entry()]} | {:error, any()}
  def list(project_id, rel_path) do
    with {:ok, dir} <- resolve(project_id, rel_path) do
      case File.ls(dir) do
        {:ok, names} ->
          entries =
            names
            |> Enum.sort()
            |> Enum.map(&entry(dir, &1))
            |> Enum.sort_by(&{!&1.isDir, String.downcase(&1.name)})

          {:ok, entries}

        {:error, :enoent} ->
          {:error, :not_found}

        {:error, :enotdir} ->
          {:error, "Not a directory"}

        {:error, reason} ->
          {:error, "Cannot list directory (#{reason})"}
      end
    end
  end

  @doc """
  Stores an uploaded file (`Plug.Upload`) inside `rel_dir`. The stored name is
  the upload's basename (an existing file with the same name is overwritten).
  Returns the entry's project-relative path.
  """
  @spec save_upload(integer(), Plug.Upload.t(), String.t()) ::
          {:ok, String.t()} | {:error, any()}
  # sobelow_skip ["Traversal.FileModule"]
  def save_upload(project_id, %Plug.Upload{filename: filename, path: tmp_path}, rel_dir) do
    name = filename |> to_string() |> Path.basename()

    cond do
      name == "" or name in [".", ".."] ->
        {:error, "Invalid file name"}

      true ->
        with {:ok, dir} <- resolve(project_id, rel_dir),
             true <- File.dir?(dir) || {:error, :not_found},
             {:ok, dest} <- resolve(project_id, Path.join(rel_dir, name)),
             :ok <- File.cp(tmp_path, dest) do
          {:ok, relative_to_root(project_id, dest)}
        else
          {:error, _} = err -> err
        end
    end
  end

  @doc "Resolves a file for download: `{:ok, absolute_path, basename}`."
  @spec resolve_download(integer(), String.t()) ::
          {:ok, String.t(), String.t()} | {:error, any()}
  def resolve_download(project_id, rel_path) do
    with {:ok, full} <- resolve(project_id, rel_path) do
      cond do
        not File.exists?(full) -> {:error, :not_found}
        File.dir?(full) -> {:error, "Cannot download a directory"}
        true -> {:ok, full, Path.basename(full)}
      end
    end
  end

  @doc """
  Creates a new directory `name` inside `rel_dir`. The name must be a plain
  basename (no separators); an existing entry with the same name is an error.
  Returns the new directory's project-relative path.
  """
  @spec mkdir(integer(), String.t(), String.t()) :: {:ok, String.t()} | {:error, any()}
  # sobelow_skip ["Traversal.FileModule"]
  def mkdir(project_id, rel_dir, name) do
    name = to_string(name || "")

    cond do
      name == "" or name in [".", ".."] or String.contains?(name, ["/", "\\"]) ->
        {:error, "Invalid folder name"}

      true ->
        with {:ok, dir} <- resolve(project_id, rel_dir),
             true <- File.dir?(dir) || {:error, :not_found},
             {:ok, dest} <- resolve(project_id, Path.join(rel_dir, name)) do
          case File.mkdir(dest) do
            :ok -> {:ok, relative_to_root(project_id, dest)}
            {:error, :eexist} -> {:error, "An entry with this name already exists"}
            {:error, reason} -> {:error, "Cannot create directory (#{reason})"}
          end
        else
          {:error, _} = err -> err
        end
    end
  end

  @doc "Creates the project's sandbox directory (and parents), if missing."
  @spec ensure_root(integer()) :: :ok | {:error, any()}
  # sobelow_skip ["Traversal.FileModule"]
  def ensure_root(project_id) do
    case File.mkdir_p(SafePath.sandbox_root(project_id)) do
      :ok -> :ok
      {:error, reason} -> {:error, "Cannot create directory (#{reason})"}
    end
  end

  @doc "Deletes a file, or a directory when empty. The project root is protected."
  @spec delete(integer(), String.t()) :: :ok | {:error, any()}
  # sobelow_skip ["Traversal.FileModule"]
  def delete(project_id, rel_path) do
    with {:ok, full} <- resolve(project_id, rel_path) do
      cond do
        full == SafePath.sandbox_root(project_id) -> {:error, "Cannot delete the project root"}
        File.dir?(full) -> rmdir(full)
        File.exists?(full) -> File.rm(full) |> rm_result()
        true -> {:error, :not_found}
      end
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────────────────

  # Client paths are relative to the project sandbox; anchor them there and
  # confine the expanded result so `../`/absolute escapes cannot leave it.
  defp resolve(project_id, rel_path) do
    base = SafePath.sandbox_root(project_id)
    full = Path.expand(Path.join(base, to_string(rel_path || "")))

    if full == base or String.starts_with?(full, base <> "/") do
      {:ok, full}
    else
      {:error, "Path escapes the project sandbox"}
    end
  end

  defp relative_to_root(project_id, full),
    do: Path.relative_to(full, SafePath.sandbox_root(project_id))

  defp entry(dir, name) do
    full = Path.join(dir, name)
    dir? = File.dir?(full)

    {size, mtime} =
      case File.stat(full, time: :posix) do
        {:ok, %File.Stat{size: s, mtime: t}} -> {s, DateTime.from_unix!(t)}
        {:error, _} -> {nil, nil}
      end

    %{name: name, isDir: dir?, size: unless(dir?, do: size), modifiedAt: mtime}
  end

  defp rmdir(full) do
    case File.rmdir(full) do
      :ok -> :ok
      {:error, :eexist} -> {:error, "Directory is not empty"}
      {:error, :enotempty} -> {:error, "Directory is not empty"}
      {:error, reason} -> {:error, "Cannot delete (#{reason})"}
    end
  end

  defp rm_result(:ok), do: :ok
  defp rm_result({:error, :enoent}), do: {:error, :not_found}
  defp rm_result({:error, reason}), do: {:error, "Cannot delete (#{reason})"}
end
