defmodule CartographBackendWeb.Plugs.AbsintheContext do
  @behaviour Plug

  def init(opts), do: opts

  def call(conn, _opts) do
    Absinthe.Plug.put_options(conn, context: %{current_user: conn.assigns[:current_user]})
  end
end
