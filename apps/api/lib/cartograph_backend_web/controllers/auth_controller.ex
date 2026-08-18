defmodule CartographBackendWeb.AuthController do
  use CartographBackendWeb, :controller

  alias CartographBackend.Accounts
  alias CartographBackendWeb.Plugs.RateLimit
  alias CartographBackendWeb.Serializers

  # ── Login ────────────────────────────────────────────────────────────────────

  def login(conn, %{"email" => email, "password" => password}) do
    # The password was right in both success branches, so the account's own
    # throttle is cleared: a few typos should not lock someone out for the rest
    # of the window. The address counter stays.
    case Accounts.authenticate(email, password) do
      {:ok, :totp_required, user} ->
        RateLimit.reset(:login, email)

        pending =
          Phoenix.Token.sign(
            CartographBackendWeb.Endpoint,
            "totp pending",
            user.id,
            signed_at: System.system_time(:second)
          )

        json(conn, %{status: "totp_required", pendingToken: pending})

      {:ok, user} ->
        RateLimit.reset(:login, email)
        token = Phoenix.Token.sign(CartographBackendWeb.Endpoint, "user auth", user.id)
        json(conn, %{status: "ok", token: token, user: Serializers.user(user)})

      {:error, :invalid_credentials} ->
        conn |> put_status(401) |> json(%{error: "Invalid email or password"})
    end
  end

  # ── 2FA verification during login ────────────────────────────────────────────

  def verify_totp_login(conn, %{"pendingToken" => pending_token, "code" => code}) do
    case Phoenix.Token.verify(CartographBackendWeb.Endpoint, "totp pending", pending_token,
           max_age: 300
         ) do
      {:ok, user_id} ->
        with {:ok, user} <- Accounts.get_user(user_id),
             :ok <- Accounts.verify_totp(user, code) do
          RateLimit.reset(:totp, pending_token)
          token = Phoenix.Token.sign(CartographBackendWeb.Endpoint, "user auth", user.id)
          json(conn, %{status: "ok", token: token, user: Serializers.user(user)})
        else
          {:error, :not_found} -> conn |> put_status(401) |> json(%{error: "Invalid session"})
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
      {:ok, _} -> json(conn, %{ok: true})
      {:error, :invalid_code} -> conn |> put_status(422) |> json(%{error: "Invalid code"})
    end
  end

  @doc """
  Turns 2FA off, which needs the account password.

  Without it, anyone holding a session token — a borrowed laptop, a stolen
  token — strips the second factor off the account and keeps the password as
  the only thing standing in the way of a permanent login.
  """
  def totp_disable(conn, params) do
    user = conn.assigns.current_user

    case Accounts.verify_password(user, params["password"]) do
      :ok ->
        {:ok, _} = Accounts.disable_totp(user)
        json(conn, %{ok: true})

      {:error, :invalid_credentials} ->
        conn |> put_status(401) |> json(%{error: "Incorrect password"})
    end
  end
end
