defmodule CartographBackendWeb.ApiTokenController do
  use CartographBackendWeb, :controller
  alias CartographBackend.Accounts

  def index(conn, _params) do
    tokens = Accounts.list_api_tokens(conn.assigns.current_user)
    json(conn, %{tokens: Enum.map(tokens, &serialize/1)})
  end

  def create(conn, params) do
    name = Map.get(params, "name", "")
    expires_at = parse_expires(Map.get(params, "expiresAt"))

    case Accounts.create_api_token(conn.assigns.current_user, name, expires_at) do
      {:ok, token, raw} ->
        conn
        |> put_status(:created)
        |> json(%{token: serialize(token), rawToken: raw})

      {:error, changeset} ->
        unprocessable(conn, changeset)
    end
  end

  def delete(conn, %{"id" => id}) do
    case Accounts.revoke_api_token(conn.assigns.current_user, String.to_integer(id)) do
      {:ok, _} ->
        send_resp(conn, 204, "")

      {:error, :not_found} ->
        conn |> put_status(404) |> json(%{error: "not found"})
    end
  end

  defp serialize(t) do
    %{
      id: t.id,
      name: t.name,
      prefix: t.prefix,
      lastUsedAt: format_dt(t.last_used_at),
      expiresAt: format_dt(t.expires_at),
      createdAt: format_dt(t.inserted_at)
    }
  end

  defp format_dt(nil), do: nil
  defp format_dt(dt), do: DateTime.to_iso8601(dt)

  defp parse_expires(nil), do: nil
  defp parse_expires(""), do: nil

  defp parse_expires(s) do
    case DateTime.from_iso8601(s) do
      {:ok, dt, _} -> dt
      _ -> nil
    end
  end
end
