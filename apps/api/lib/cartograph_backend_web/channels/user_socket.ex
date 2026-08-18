defmodule CartographBackendWeb.UserSocket do
  use Phoenix.Socket

  use Absinthe.Phoenix.Socket, schema: CartographBackendWeb.Schema

  @impl true
  def connect(params, socket, _connect_info) do
    case authenticate(params) do
      {:ok, user} ->
        socket =
          Absinthe.Phoenix.Socket.put_options(socket, context: %{current_user: user})

        {:ok, assign(socket, :current_user, user)}

      :error ->
        :error
    end
  end

  @impl true
  def id(%{assigns: %{current_user: %{id: id}}}), do: "user_socket:#{id}"
  def id(_socket), do: nil

  # Verifies the same session token as the REST AuthPlug, through the same
  # module, so a revoked session cannot keep a socket open. A connection
  # without a valid token is rejected so subscriptions never run anonymously.
  defp authenticate(params) do
    case CartographBackendWeb.SessionToken.verify(params["token"]) do
      {:ok, user, _jti} -> {:ok, user}
      :error -> :error
    end
  end
end
