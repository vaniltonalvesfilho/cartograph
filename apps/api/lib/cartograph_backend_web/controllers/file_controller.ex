defmodule CartographBackendWeb.FileController do
  use CartographBackendWeb, :controller

  alias CartographBackend.{Authorization, Files, Groups}

  # Access model (per-project only):
  #
  #   * Every request targets one project (`:project_id`). All paths are
  #     relative to that project's sandbox (`<data root>/projects/<id>`), the
  #     same dir the project's jobs are confined to.
  #   * `:view` (10) lists and downloads; `:edit` (30) uploads, creates folders
  #     and deletes. Admins pass unconditionally.
  #   * Nonexistent and forbidden projects are indistinguishable (no
  #     enumeration oracle) — same fail-closed shape as the job steps.

  def index(conn, %{"project_id" => project_id} = params) do
    path = params["path"] || ""

    with {:ok, project} <- authorize(conn, project_id, :view),
         :ok <- Files.ensure_root(project.id),
         {:ok, entries} <- result(conn, Files.list(project.id, path)) do
      json(conn, %{path: path, canWrite: can_write?(conn, project), entries: entries})
    else
      {:error, conn} -> conn
    end
  end

  def create(conn, %{"project_id" => project_id, "file" => %Plug.Upload{} = upload} = params) do
    path = params["path"] || ""

    with {:ok, project} <- authorize(conn, project_id, :edit),
         :ok <- Files.ensure_root(project.id),
         {:ok, rel_path} <- result(conn, Files.save_upload(project.id, upload, path)) do
      conn |> put_status(201) |> json(%{path: rel_path})
    else
      {:error, conn} -> conn
    end
  end

  def create(conn, _params) do
    conn |> put_status(400) |> json(%{error: "Missing file"})
  end

  def mkdir(conn, %{"project_id" => project_id, "name" => name} = params) do
    path = params["path"] || ""

    with {:ok, project} <- authorize(conn, project_id, :edit),
         :ok <- Files.ensure_root(project.id),
         {:ok, rel_path} <- result(conn, Files.mkdir(project.id, path, name)) do
      conn |> put_status(201) |> json(%{path: rel_path})
    else
      {:error, conn} -> conn
    end
  end

  def mkdir(conn, _params) do
    conn |> put_status(400) |> json(%{error: "Missing name"})
  end

  @sobelow_skip ["Traversal.SendDownload"]
  def download(conn, %{"project_id" => project_id, "path" => path}) do
    with {:ok, project} <- authorize(conn, project_id, :view),
         {:ok, full, name} <- result(conn, Files.resolve_download(project.id, path)) do
      send_download(conn, {:file, full}, filename: name)
    else
      {:error, conn} -> conn
    end
  end

  def delete(conn, %{"project_id" => project_id, "path" => path}) do
    with {:ok, project} <- authorize(conn, project_id, :edit),
         :ok <- result(conn, Files.delete(project.id, path)) do
      send_resp(conn, 204, "")
    else
      {:error, conn} -> conn
    end
  end

  # ── Authorization ─────────────────────────────────────────────────────────────

  # Resolves and authorizes the project in one step. Returns `{:ok, project}`
  # or `{:error, forbidden_conn}` — a missing project looks like a forbidden one.
  defp authorize(conn, project_id, action) do
    user = conn.assigns.current_user

    with {pid, ""} <- Integer.parse(to_string(project_id)),
         {:ok, project} <- Groups.get_project(pid),
         :ok <- Authorization.authorize(user, action, project) do
      {:ok, project}
    else
      _ -> {:error, forbidden(conn)}
    end
  end

  defp can_write?(conn, project),
    do: Authorization.can?(conn.assigns.current_user, :edit, project)

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
