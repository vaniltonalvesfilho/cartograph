defmodule CartographBackendWeb.AuthController do
  use CartographBackendWeb, :controller

  alias CartographBackend.Accounts
  alias CartographBackendWeb.Serializers

  # ── Login ────────────────────────────────────────────────────────────────────

  def login(conn, %{"email" => email, "password" => password}) do
    case Accounts.authenticate(email, password) do
      {:ok, :totp_required, user} ->
        pending = Phoenix.Token.sign(
          CartographBackendWeb.Endpoint,
          "totp pending",
          user.id,
          signed_at: System.system_time(:second)
        )
        json(conn, %{status: "totp_required", pendingToken: pending})

      {:ok, user} ->
        token = Phoenix.Token.sign(CartographBackendWeb.Endpoint, "user auth", user.id)
        json(conn, %{status: "ok", token: token, user: Serializers.user(user)})

      {:error, :invalid_credentials} ->
        conn |> put_status(401) |> json(%{error: "Invalid email or password"})
    end
  end

  # ── 2FA verification during login ────────────────────────────────────────────

  def verify_totp_login(conn, %{"pendingToken" => pending_token, "code" => code}) do
    case Phoenix.Token.verify(CartographBackendWeb.Endpoint, "totp pending", pending_token, max_age: 300) do
      {:ok, user_id} ->
        with {:ok, user} <- Accounts.get_user(user_id),
             :ok         <- Accounts.verify_totp(user, code) do
          token = Phoenix.Token.sign(CartographBackendWeb.Endpoint, "user auth", user.id)
          json(conn, %{status: "ok", token: token, user: Serializers.user(user)})
        else
          {:error, :not_found}    -> conn |> put_status(401) |> json(%{error: "Invalid session"})
          {:error, :invalid_code} -> conn |> put_status(401) |> json(%{error: "Invalid code"})
        end

      {:error, _} ->
        conn |> put_status(401) |> json(%{error: "Session expired, please log in again"})
    end
  end

  # ── Current user ─────────────────────────────────────────────────────────────

  def me(%{assigns: %{current_user: user}} = conn, _params) do
    json(conn, Serializers.user(user))
  end

  # ── 2FA setup (protected) ────────────────────────────────────────────────────

  def totp_setup(conn, _params) do
    user = conn.assigns.current_user
    secret = Accounts.generate_totp_secret()
    {:ok, user} = Accounts.save_totp_secret(user, secret)
    uri = Accounts.totp_provisioning_uri(user, secret)
    json(conn, %{secret: Base.encode32(secret, padding: false), uri: uri})
  end

  def totp_enable(conn, %{"code" => code}) do
    user = conn.assigns.current_user
    case Accounts.enable_totp(user, code) do
      {:ok, _}                -> json(conn, %{ok: true})
      {:error, :invalid_code} -> conn |> put_status(422) |> json(%{error: "Invalid code"})
    end
  end

  def totp_disable(conn, _params) do
    user = conn.assigns.current_user
    {:ok, _} = Accounts.disable_totp(user)
    json(conn, %{ok: true})
  end
end
