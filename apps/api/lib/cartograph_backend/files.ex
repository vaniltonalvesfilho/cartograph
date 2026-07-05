defmodule CartographBackend.Files do
  @moduledoc """
  Manages the job data sandbox (`Steps.SafePath.root/0`) for the dashboard's
  Files area: list a directory, store an upload, resolve a download and delete
  entries. Every path from the client is RELATIVE to the sandbox root and is
  re-confined through `SafePath.resolve/1`, so `../`/absolute escapes fail the
  same way they do for DSL steps.
  """

  alias CartographBackend.Steps.SafePath

  @type entry :: %{
          name: String.t(),
          isDir: boolean(),
          size: non_neg_integer() | nil,
          modifiedAt: DateTime.t() | nil
        }

  @doc "Lists a directory (path relative to the sandbox root, \"\" = root)."
  @spec list(String.t()) :: {:ok, [entry()]} | {:error, String.t()}
  def list(rel_path) do
    with {:ok, dir} <- resolve(rel_path) do
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
  Returns the entry's sandbox-relative path.
  """
  @spec save_upload(Plug.Upload.t(), String.t()) :: {:ok, String.t()} | {:error, any()}
  def save_upload(%Plug.Upload{filename: filename, path: tmp_path}, rel_dir) do
    name = filename |> to_string() |> Path.basename()

    cond do
      name == "" or name in [".", ".."] ->
        {:error, "Invalid file name"}

      true ->
        with {:ok, dir} <- resolve(rel_dir),
             true <- File.dir?(dir) || {:error, :not_found},
             {:ok, dest} <- resolve(Path.join(rel_dir, name)),
             :ok <- File.cp(tmp_path, dest) do
          {:ok, relative_to_root(dest)}
        else
          {:error, _} = err -> err
        end
    end
  end

  @doc "Resolves a file for download: `{:ok, absolute_path, basename}`."
  @spec resolve_download(String.t()) :: {:ok, String.t(), String.t()} | {:error, any()}
  def resolve_download(rel_path) do
    with {:ok, full} <- resolve(rel_path) do
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
  Returns the new directory's sandbox-relative path.
  """
  @spec mkdir(String.t(), String.t()) :: {:ok, String.t()} | {:error, any()}
  def mkdir(rel_dir, name) do
    name = to_string(name || "")

    cond do
      name == "" or name in [".", ".."] or String.contains?(name, ["/", "\\"]) ->
        {:error, "Invalid folder name"}

      true ->
        with {:ok, dir} <- resolve(rel_dir),
             true <- File.dir?(dir) || {:error, :not_found},
             {:ok, dest} <- resolve(Path.join(rel_dir, name)) do
          case File.mkdir(dest) do
            :ok -> {:ok, relative_to_root(dest)}
            {:error, :eexist} -> {:error, "An entry with this name already exists"}
            {:error, reason} -> {:error, "Cannot create directory (#{reason})"}
          end
        else
          {:error, _} = err -> err
        end
    end
  end

  @doc "Creates a directory (and parents) inside the sandbox, if missing."
  @spec ensure_dir(String.t()) :: :ok | {:error, any()}
  def ensure_dir(rel_path) do
    with {:ok, dir} <- resolve(rel_path) do
      case File.mkdir_p(dir) do
        :ok -> :ok
        {:error, reason} -> {:error, "Cannot create directory (#{reason})"}
      end
    end
  end

  @doc "Deletes a file, or a directory when empty. The root itself is protected."
  @spec delete(String.t()) :: :ok | {:error, any()}
  def delete(rel_path) do
    with {:ok, full} <- resolve(rel_path) do
      cond do
        full == SafePath.root() -> {:error, "Cannot delete the data root"}
        File.dir?(full) -> rmdir(full)
        File.exists?(full) -> File.rm(full) |> rm_result()
        true -> {:error, :not_found}
      end
    end
  end

  # ── Helpers ───────────────────────────────────────────────────────────────────

  # Client paths are relative to the sandbox root; anchor them there and let
  # SafePath do the escape check on the expanded result.
  defp resolve(rel_path) do
    SafePath.resolve(Path.join(SafePath.root(), to_string(rel_path || "")))
  end

  defp relative_to_root(full), do: Path.relative_to(full, SafePath.root())

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
