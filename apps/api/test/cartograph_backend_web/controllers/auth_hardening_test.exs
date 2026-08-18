defmodule CartographBackendWeb.AuthHardeningTest do
  @moduledoc """
  Regressions for the credential-handling findings of security survey 01:
  brute-force throttling on login and 2FA, TOTP replay, and turning 2FA off
  without proving who you are.

  Not async: the rate limiter is one ETS table shared by the whole node.
  """
  use CartographBackendWeb.ConnCase, async: false

  alias CartographBackend.Accounts
  alias CartographBackend.Accounts.User
  alias CartographBackend.RateLimiter
  alias CartographBackend.Repo

  @password "correct horse battery"

  setup do
    RateLimiter.reset_all()

    # Windows are fixed, so a test that straddles a window boundary sees its
    # counters reset mid-run. Stretch the window to a day for the duration of
    # the test: same limits, but the boundary is no longer in reach.
    previous = Application.get_env(:cartograph_backend, CartographBackendWeb.Plugs.RateLimit)

    Application.put_env(:cartograph_backend, CartographBackendWeb.Plugs.RateLimit,
      login: [address: {60, :timer.hours(24)}, identifier: {10, :timer.hours(24)}],
      totp: [address: {60, :timer.hours(24)}, identifier: {5, :timer.hours(24)}]
    )

    on_exit(fn ->
      Application.put_env(:cartograph_backend, CartographBackendWeb.Plugs.RateLimit, previous)
      RateLimiter.reset_all()
    end)

    user = insert_user("agente@example.com")
    %{user: user}
  end

  defp insert_user(email) do
    %User{}
    |> User.changeset(%{name: "Agente", email: email, password: @password})
    |> Repo.insert!()
  end

  defp with_totp(user) do
    secret = Accounts.generate_totp_secret()
    {:ok, user} = Accounts.save_totp_secret(user, secret)
    {:ok, user} = Accounts.enable_totp(user, NimbleTOTP.verification_code(secret))
    {user, secret}
  end

  defp login(conn, email, password) do
    post(conn, ~p"/api/auth/login", %{"email" => email, "password" => password})
  end

  # ── CG-02: login brute force ─────────────────────────────────────────────────

  describe "login throttling" do
    test "stops guessing a single account after the identifier budget", %{
      conn: conn,
      user: user
    } do
      for _ <- 1..10 do
        assert login(build_conn(), user.email, "wrong").status == 401
      end

      blocked = login(conn, user.email, "wrong")

      assert blocked.status == 429
      assert ["" <> retry_after] = get_resp_header(blocked, "retry-after")
      assert String.to_integer(retry_after) > 0
    end

    test "the right password still works once the budget is spent by another account", %{
      user: user
    } do
      other = insert_user("outro@example.com")

      for _ <- 1..10 do
        assert login(build_conn(), other.email, "wrong").status == 401
      end

      # Same address, different account: the address budget (60) is untouched.
      assert json_response(login(build_conn(), user.email, @password), 200)["status"] == "ok"
    end

    test "a successful login clears that account's counter", %{user: user} do
      for _ <- 1..9 do
        assert login(build_conn(), user.email, "wrong").status == 401
      end

      assert json_response(login(build_conn(), user.email, @password), 200)["status"] == "ok"

      # Without the reset, only one attempt would be left in the window.
      for _ <- 1..10 do
        assert login(build_conn(), user.email, "wrong").status == 401
      end
    end
  end

  # ── CG-03: 2FA brute force ───────────────────────────────────────────────────

  describe "2FA verification throttling" do
    test "stops guessing the 6-digit code on one pending session", %{conn: conn, user: user} do
      {user, _secret} = with_totp(user)

      pending =
        json_response(login(build_conn(), user.email, @password), 200)["pendingToken"]

      assert is_binary(pending)

      for _ <- 1..5 do
        resp =
          post(build_conn(), ~p"/api/auth/2fa/verify", %{
            "pendingToken" => pending,
            "code" => "000000"
          })

        assert resp.status == 401
      end

      blocked =
        post(conn, ~p"/api/auth/2fa/verify", %{"pendingToken" => pending, "code" => "000000"})

      assert blocked.status == 429
    end
  end

  # ── CG-05: TOTP replay ───────────────────────────────────────────────────────

  describe "TOTP replay" do
    test "the same code is not accepted twice", %{user: user} do
      {user, secret} = with_totp(user)
      code = NimbleTOTP.verification_code(secret)

      # `enable_totp` already burned the code for this step, so re-read the
      # user and check the step is refused rather than the first call winning.
      user = Repo.get!(User, user.id)

      assert {:error, :invalid_code} = Accounts.verify_totp(user, code)
    end

    test "a valid code is accepted once, then burned", %{user: user} do
      {user, secret} = with_totp(user)

      # Clear the burn left by `enable_totp` so the current step is free again,
      # which is the state a normal login starts from.
      {:ok, user} = user |> User.totp_changeset(%{totp_last_used_at: nil}) |> Repo.update()

      code = NimbleTOTP.verification_code(secret)
      assert :ok = Accounts.verify_totp(user, code)

      user = Repo.get!(User, user.id)
      assert {:error, :invalid_code} = Accounts.verify_totp(user, code)
    end
  end

  # ── CG-06: disabling 2FA ─────────────────────────────────────────────────────

  describe "disabling 2FA" do
    setup %{user: user} do
      {user, _secret} = with_totp(user)
      %{user: user, conn: authenticate(build_conn(), user)}
    end

    test "a session token alone is not enough", %{conn: conn, user: user} do
      assert delete(conn, ~p"/api/auth/2fa/disable").status == 401
      assert Repo.get!(User, user.id).totp_enabled
    end

    test "a wrong password is not enough", %{conn: conn, user: user} do
      assert delete(conn, ~p"/api/auth/2fa/disable", %{"password" => "nope"}).status == 401
      assert Repo.get!(User, user.id).totp_enabled
    end

    test "the account password turns it off", %{conn: conn, user: user} do
      assert json_response(
               delete(conn, ~p"/api/auth/2fa/disable", %{"password" => @password}),
               200
             )["ok"]

      user = Repo.get!(User, user.id)
      refute user.totp_enabled
      refute user.totp_secret
    end
  end
end
