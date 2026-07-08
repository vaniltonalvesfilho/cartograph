defmodule CartographBackendWeb.ProjectController do
  use CartographBackendWeb, :controller

  alias CartographBackend.{Groups, Accounts, Authorization}
  alias CartographBackendWeb.{Serializers, Params}

  def index(conn, params) do
    user = conn.assigns.current_user
    levels = Authorization.scope(user).projects

    with {:ok, opts} <- index_opts(params) do
      projects =
        Groups.list_projects(opts)
        |> Enum.filter(&Map.has_key?(levels, &1.id))
        |> Enum.map(&Serializers.project(&1, Map.fetch!(levels, &1.id)))

      json(conn, projects)
    else
      {:error, :bad_request} -> bad_request(conn)
    end
  end

  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, pid} <- Params.int(id),
         {:ok, project} <- Groups.get_project(pid),
         :ok <- Authorization.authorize(user, :view, project) do
      json(conn, Serializers.project(project, Authorization.effective_level(user, project)))
    else
      {:error, :bad_request} -> bad_request(conn)
      {:error, :forbidden} -> forbidden(conn)
      {:error, :not_found} -> send_resp(conn, 404, "")
    end
  end

  def create(conn, params) do
    user = conn.assigns.current_user
    attrs = take_attrs(params)
    group_id = attrs["group_id"]

    with :ok <- Authorization.authorize_create_project(user, group_id),
         {:ok, project} <- Groups.create_project(attrs) do
      Accounts.grant_owner(user, "project", project.id)
      level = Authorization.effective_level(user, project)
      conn |> put_status(201) |> json(Serializers.project(project, level))
    else
      {:error, :forbidden} -> forbidden(conn)
      {:error, %Ecto.Changeset{} = cs} -> unprocessable(conn, cs)
    end
  end

  def update(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user
    attrs = take_attrs(params)

    with {:ok, pid} <- Params.int(id),
         {:ok, project} <- Groups.get_project(pid),
         :ok <- Authorization.authorize(user, :edit, project),
         :ok <-
           Authorization.authorize_move_project(user, Map.get(attrs, "group_id", :unchanged)),
         {:ok, project} <- Groups.update_project(project.id, attrs) do
      json(conn, Serializers.project(project, Authorization.effective_level(user, project)))
    else
      {:error, :bad_request} -> bad_request(conn)
      {:error, :forbidden} -> forbidden(conn)
      {:error, :not_found} -> send_resp(conn, 404, "")
      {:error, cs} -> unprocessable(conn, cs)
    end
  end

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, pid} <- Params.int(id),
         {:ok, project} <- Groups.get_project(pid),
         :ok <- Authorization.authorize(user, :delete, project),
         {:ok, _} <- Groups.delete_project(project.id) do
      send_resp(conn, 204, "")
    else
      {:error, :bad_request} -> bad_request(conn)
      {:error, :forbidden} -> forbidden(conn)
      {:error, :not_found} -> send_resp(conn, 404, "")
    end
  end

  defp index_opts(params) do
    case params["groupId"] do
      nil -> {:ok, []}
      "root" -> {:ok, [group_id: :root]}
      id -> with {:ok, gid} <- Params.int(id), do: {:ok, [group_id: gid]}
    end
  end

  defp take_attrs(params) do
    params
    |> Map.take(["name", "description", "groupId", "position"])
    |> Map.new(fn {k, v} -> {snake(k), v} end)
  end

  defp snake("groupId"), do: "group_id"
  defp snake(k), do: k
end
