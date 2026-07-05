defmodule CartographBackendWeb.Plugs.RequireAuth do
  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def init(opts), do: opts

  def call(%{assigns: %{current_user: nil}} = conn, _opts) do
    conn |> put_status(401) |> json(%{error: "Unauthorized"}) |> halt()
  end
  def call(conn, _opts), do: conn
end
