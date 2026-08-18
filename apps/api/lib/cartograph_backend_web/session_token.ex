defmodule CartographBackendWeb.SessionToken do
  @moduledoc """
  The dashboard's bearer token: minted at login, checked by the REST plug and
  by the WebSocket.

  It is a `Phoenix.Token` — signed, not stored — so the signature alone says
  nothing about whether the session is still wanted. It carries the `jti` of a
  `user_sessions` row, and verification checks that row is live, which is what
  gives signing out and revoking on a password change any effect.

  Both entry points go through here so they cannot drift apart: a socket that
  accepted tokens the REST API rejects would be a way around revocation.
  """

  alias CartographBackend.Accounts
  alias CartographBackendWeb.Endpoint

  @salt "user auth"

  @doc "Signs a token for an open session."
  def sign(user_id, jti), do: Phoenix.Token.sign(Endpoint, @salt, {user_id, jti})

  @doc """
  Returns `{:ok, user, jti}` for a token that is in date and names a live
  session, `:error` otherwise.

  Tokens minted before sessions existed carry a bare user id and no longer
  verify, which signs those users out once.
  """
  def verify(token) when is_binary(token) do
    with {:ok, {user_id, jti}} <-
           Phoenix.Token.verify(Endpoint, @salt, token, max_age: max_age()),
         true <- Accounts.session_active?(user_id, jti),
         {:ok, user} <- Accounts.get_user(user_id) do
      {:ok, user, jti}
    else
      _ -> :error
    end
  end

  def verify(_), do: :error

  @doc "How long a signed session token stays valid, in seconds."
  def max_age,
    do: Application.get_env(:cartograph_backend, :session_max_age_seconds, 86_400 * 7)
end
