defmodule CartographBackendWeb.GroupController do
  use CartographBackendWeb, :controller

  alias CartographBackend.{Groups, Accounts, Authorization}
  alias CartographBackendWeb.{Serializers, Params}

  def index(conn, _params) do
    user = conn.assigns.current_user
    levels = Authorization.scope(user).groups

    groups =
      Groups.list_groups()
      |> Enum.filter(&Map.has_key?(levels, &1.id))
      |> Enum.map(&Serializers.group(&1, Map.fetch!(levels, &1.id)))

    json(conn, groups)
  end

  def show(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, gid} <- Params.int(id),
         {:ok, group} <- Groups.get_group(gid),
         :ok <- Authorization.authorize(user, :view, group) do
      json(conn, Serializers.group(group, Authorization.effective_level(user, group)))
    else
      {:error, :bad_request} -> bad_request(conn)
      {:error, :forbidden} -> forbidden(conn)
      {:error, :not_found} -> send_resp(conn, 404, "")
    end
  end

  def create(conn, params) do
    user = conn.assigns.current_user
    attrs = take_attrs(params)
    parent_id = attrs["parent_id"]

    with :ok <- Authorization.authorize_create_group(user, parent_id),
         {:ok, group} <- Groups.create_group(attrs) do
      Accounts.grant_owner(user, "group", group.id)
      level = Authorization.effective_level(user, group)
      conn |> put_status(201) |> json(Serializers.group(group, level))
    else
      {:error, :forbidden} -> forbidden(conn)
      {:error, %Ecto.Changeset{} = cs} -> unprocessable(conn, cs)
    end
  end

  def update(conn, %{"id" => id} = params) do
    user = conn.assigns.current_user
    attrs = take_attrs(params)

    with {:ok, gid} <- Params.int(id),
         {:ok, group} <- Groups.get_group(gid),
         :ok <- Authorization.authorize(user, :edit, group),
         {:ok, group} <- Groups.update_group(group.id, attrs) do
      json(conn, Serializers.group(group, Authorization.effective_level(user, group)))
    else
      {:error, :bad_request} -> bad_request(conn)
      {:error, :forbidden} -> forbidden(conn)
      {:error, :not_found} -> send_resp(conn, 404, "")
      {:error, :cycle_detected} -> conn |> put_status(400) |> json(%{error: "cycle_detected"})
      {:error, cs} -> unprocessable(conn, cs)
    end
  end

  def delete(conn, %{"id" => id}) do
    user = conn.assigns.current_user

    with {:ok, gid} <- Params.int(id),
         {:ok, group} <- Groups.get_group(gid),
         :ok <- Authorization.authorize(user, :delete, group),
         {:ok, _} <- Groups.delete_group(group.id) do
      send_resp(conn, 204, "")
    else
      {:error, :bad_request} -> bad_request(conn)
      {:error, :forbidden} -> forbidden(conn)
      {:error, :not_found} -> send_resp(conn, 404, "")
    end
  end

  defp take_attrs(params) do
    params
    |> Map.take(["name", "description", "parentId", "position"])
    |> Map.new(fn {k, v} -> {snake(k), v} end)
  end

  defp snake("parentId"), do: "parent_id"
  defp snake(k), do: k
end
