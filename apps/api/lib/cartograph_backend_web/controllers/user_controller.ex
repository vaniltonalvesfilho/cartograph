defmodule CartographBackendWeb.UserController do
  use CartographBackendWeb, :controller

  alias CartographBackend.Accounts
  alias CartographBackendWeb.{Serializers, Params}

  def index(conn, _params) do
    with :ok <- require_admin(conn) do
      json(conn, Enum.map(Accounts.list_users(), &Serializers.user/1))
    else
      {:error, conn} -> conn
    end
  end

  # Minimal directory for member pickers — any authenticated user.
  def pickable(conn, _params) do
    json(conn, Accounts.pickable_users())
  end

  def create(conn, params) do
    with :ok <- require_admin(conn) do
      attrs =
        Map.take(params, ["name", "email", "password"])
        |> maybe_put_admin(params)

      case Accounts.admin_create_user(attrs) do
        {:ok, user} ->
          CartographBackend.Mailing.send_welcome_async(user)
          conn |> put_status(201) |> json(Serializers.user(user))

        {:error, cs} ->
          unprocessable(conn, cs)
      end
    else
      {:error, conn} -> conn
    end
  end

  def update(conn, %{"id" => id} = params) do
    with {:ok, target_id} <- Params.int(id),
         :ok <- require_admin(conn),
         :ok <- guard_last_admin_demotion(conn, target_id, params) do
      attrs =
        Map.take(params, ["name", "email", "password"])
        |> maybe_put_admin(params)

      case Accounts.admin_update_user(target_id, attrs) do
        {:ok, user} -> json(conn, Serializers.user(user))
        {:error, :not_found} -> send_resp(conn, 404, "")
        {:error, cs} -> unprocessable(conn, cs)
      end
    else
      {:error, :bad_request} -> conn |> put_status(400) |> json(%{error: "Bad request"})
      {:error, conn} -> conn
    end
  end

  def delete(conn, %{"id" => id}) do
    with {:ok, target_id} <- Params.int(id),
         :ok <- require_admin(conn),
         :ok <- guard_self(conn, target_id, "You cannot delete yourself"),
         :ok <- guard_last_admin_deletion(conn, target_id) do
      case Accounts.delete_user(target_id) do
        {:ok, _} -> send_resp(conn, 204, "")
        {:error, :not_found} -> send_resp(conn, 404, "")
      end
    else
      {:error, :bad_request} -> conn |> put_status(400) |> json(%{error: "Bad request"})
      {:error, conn} -> conn
    end
  end

  # Block self-targeting actions (e.g. deleting your own account).
  defp guard_self(conn, target_id, message) do
    if conn.assigns.current_user.id == target_id do
      {:error, conn |> put_status(400) |> json(%{error: message}) |> halt()}
    else
      :ok
    end
  end

  # Refuse to remove the admin flag from the last remaining admin.
  defp guard_last_admin_demotion(conn, target_id, params) do
    demoting? = Map.get(params, "isAdmin") == false

    with true <- demoting?,
         {:ok, %{is_admin: true}} <- Accounts.get_user(target_id),
         1 <- Accounts.count_admins() do
      {:error,
       conn
       |> put_status(400)
       |> json(%{error: "Cannot remove the last administrator"})
       |> halt()}
    else
      _ -> :ok
    end
  end

  defp guard_last_admin_deletion(conn, target_id) do
    with {:ok, %{is_admin: true}} <- Accounts.get_user(target_id),
         1 <- Accounts.count_admins() do
      {:error,
       conn
       |> put_status(400)
       |> json(%{error: "Cannot delete the last administrator"})
       |> halt()}
    else
      _ -> :ok
    end
  end

  defp maybe_put_admin(attrs, params) do
    case Map.get(params, "isAdmin") do
      nil -> attrs
      v -> Map.put(attrs, "is_admin", v)
    end
  end
end
