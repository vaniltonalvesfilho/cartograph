defmodule CartographBackendWeb.Plugs.AuthPlug do
  import Plug.Conn
  alias CartographBackend.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> resolve_token(conn, token)
      _ -> assign(conn, :current_user, nil)
    end
  end

  defp resolve_token(conn, "cg_" <> _ = token) do
    case Accounts.verify_api_token(token) do
      {:ok, user} -> assign(conn, :current_user, user)
      _ -> assign(conn, :current_user, nil)
    end
  end

  defp resolve_token(conn, token) do
    case CartographBackendWeb.SessionToken.verify(token) do
      {:ok, user, jti} -> conn |> assign(:current_user, user) |> assign(:session_jti, jti)
      :error -> assign(conn, :current_user, nil)
    end
  end
end
