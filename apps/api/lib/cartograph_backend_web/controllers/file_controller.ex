defmodule CartographBackendWeb.FileController do
  use CartographBackendWeb, :controller

  alias CartographBackend.{Authorization, Files, Groups}

  # Access model (v2, per-project scoping):
  #
  #   * admin — whole sandbox, as in v1.
  #   * non-admin — only `projects/<id>/**` for projects where they hold a
  #     membership level (cascaded from the group): `:view` (10) to list and
  #     download, `:edit` (30) to upload and delete. The sandbox root listing
  #     is synthesized as "one folder per visible project". Everything else
  #     (inbox/, sample/, other projects…) is forbidden — same fail-closed
  #     shape as the job steps, which confine project jobs to their own dir.

  def index(conn, params) do
    path = params["path"] || ""
    user = conn.assigns.current_user

    if not user.is_admin and root?(path) do
      json(conn, %{path: "", canWrite: false, entries: project_entries(user)})
    else
      with :ok <- authorize(conn, path, :view),
           :ok <- provision(user, path),
           {:ok, entries} <- result(conn, Files.list(path)) do
        json(conn, %{path: path, canWrite: can_write?(user, path), entries: entries})
      else
        {:error, conn} -> conn
      end
    end
  end

  def create(conn, %{"file" => %Plug.Upload{} = upload} = params) do
    path = params["path"] || ""

    with :ok <- authorize(conn, path, :edit),
         :ok <- provision(conn.assigns.current_user, path),
         {:ok, rel_path} <- result(conn, Files.save_upload(upload, path)) do
      conn |> put_status(201) |> json(%{path: rel_path})
    else
      {:error, conn} -> conn
    end
  end

  def create(conn, _params) do
    conn |> put_status(400) |> json(%{error: "Missing file"})
  end

  def mkdir(conn, %{"name" => name} = params) do
    path = params["path"] || ""

    with :ok <- authorize(conn, path, :edit),
         :ok <- provision(conn.assigns.current_user, path),
         {:ok, rel_path} <- result(conn, Files.mkdir(path, name)) do
      conn |> put_status(201) |> json(%{path: rel_path})
    else
      {:error, conn} -> conn
    end
  end

  def mkdir(conn, _params) do
    conn |> put_status(400) |> json(%{error: "Missing name"})
  end

  def download(conn, %{"path" => path}) do
    with :ok <- authorize(conn, path, :view),
         {:ok, full, name} <- result(conn, Files.resolve_download(path)) do
      send_download(conn, {:file, full}, filename: name)
    else
      {:error, conn} -> conn
    end
  end

  def delete(conn, %{"path" => path}) do
    with :ok <- authorize(conn, path, :delete_file),
         :ok <- result(conn, Files.delete(path)) do
      send_resp(conn, 204, "")
    else
      {:error, conn} -> conn
    end
  end

  # ── Authorization ─────────────────────────────────────────────────────────────

  # Files don't have per-file ACLs; write actions ride the project's :edit.
  defp required_action(:delete_file), do: :edit
  defp required_action(action), do: action

  defp authorize(%{assigns: %{current_user: %{is_admin: true}}}, _path, _action), do: :ok

  defp authorize(conn, path, action) do
    user = conn.assigns.current_user

    with {:project, pid} <- project_scope(path),
         {:ok, project} <- Groups.get_project(pid),
         :ok <- Authorization.authorize(user, required_action(action), project) do
      :ok
    else
      # Nonexistent and forbidden are indistinguishable — no enumeration oracle.
      _ -> {:error, forbidden(conn)}
    end
  end

  defp can_write?(%{is_admin: true}, _path), do: true

  defp can_write?(user, path) do
    with {:project, pid} <- project_scope(path),
         {:ok, project} <- Groups.get_project(pid) do
      Authorization.can?(user, :edit, project)
    else
      _ -> false
    end
  end

  # `projects/<id>[/...]` → {:project, id}; anything else → :other
  defp project_scope(path) do
    case segments(path) do
      ["projects", raw | _] ->
        case Integer.parse(raw) do
          {pid, ""} -> {:project, pid}
          _ -> :other
        end

      _ ->
        :other
    end
  end

  defp segments(path), do: path |> to_string() |> String.split("/", trim: true)

  defp root?(path), do: segments(path) in [[], ["."]]

  # A project's dir is created lazily on first authorized access, so members
  # land on an empty folder instead of a 404.
  defp provision(%{is_admin: true}, _path), do: :ok

  defp provision(_user, path) do
    case project_scope(path) do
      {:project, pid} -> Files.ensure_dir("projects/#{pid}")
      :other -> :ok
    end
  end

  # Root listing for non-admins: one virtual folder per visible project
  # (membership level ≥ :view). `path` points at the real sandbox dir.
  defp project_entries(user) do
    min_view = Authorization.required_level(:view)
    levels = Authorization.scope(user).projects

    Groups.list_projects()
    |> Enum.filter(&(Map.get(levels, &1.id, 0) >= min_view))
    |> Enum.sort_by(&String.downcase(&1.name))
    |> Enum.map(fn p ->
      %{name: p.name, path: "projects/#{p.id}", isDir: true, size: nil, modifiedAt: nil}
    end)
  end

  # Maps context errors onto halted JSON responses so the `with` stays flat.
  defp result(_conn, :ok), do: :ok
  defp result(_conn, {:ok, _} = ok), do: ok
  defp result(_conn, {:ok, _, _} = ok), do: ok

  defp result(conn, {:error, :not_found}),
    do: {:error, conn |> put_status(404) |> json(%{error: "Not found"}) |> halt()}

  defp result(conn, {:error, reason}) do
    msg = if is_binary(reason), do: reason, else: "Invalid request"
    {:error, conn |> put_status(400) |> json(%{error: msg}) |> halt()}
  end
end
