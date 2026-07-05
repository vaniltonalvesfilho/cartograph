defmodule CartographBackendWeb.UserSocket do
  use Phoenix.Socket

  use Absinthe.Phoenix.Socket, schema: CartographBackendWeb.Schema

  alias CartographBackend.Accounts

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

  # Verifies the same Phoenix.Token used by the REST AuthPlug. A connection
  # without a valid token is rejected so subscriptions never run anonymously.
  defp authenticate(params) do
    with token when is_binary(token) <- params["token"],
         {:ok, user_id} <-
           Phoenix.Token.verify(CartographBackendWeb.Endpoint, "user auth", token,
             max_age: 86_400 * 30
           ),
         {:ok, user} <- Accounts.get_user(user_id) do
      {:ok, user}
    else
      _ -> :error
    end
  end
end
