defmodule CartographBackendWeb.Plugs.AuthPlug do
  import Plug.Conn
  alias CartographBackend.Accounts

  def init(opts), do: opts

  def call(conn, _opts) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> resolve_token(conn, token)
      _                    -> assign(conn, :current_user, nil)
    end
  end

  defp resolve_token(conn, "cg_" <> _ = token) do
    case Accounts.verify_api_token(token) do
      {:ok, user} -> assign(conn, :current_user, user)
      _           -> assign(conn, :current_user, nil)
    end
  end

  defp resolve_token(conn, token) do
    with {:ok, user_id} <- Phoenix.Token.verify(
           CartographBackendWeb.Endpoint,
           "user auth",
           token,
           max_age: 86_400 * 30
         ),
         {:ok, user} <- Accounts.get_user(user_id) do
      assign(conn, :current_user, user)
    else
      _ -> assign(conn, :current_user, nil)
    end
  end
end
