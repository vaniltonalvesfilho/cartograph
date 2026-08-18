defmodule CartographBackendWeb.SessionRevocationTest do
  @moduledoc """
  CG-07: session tokens were signed, never stored, and good for 30 days, so
  there was no way to end one — signing out only forgot the token client-side.
  """
  use CartographBackendWeb.ConnCase, async: true

  alias CartographBackend.Accounts
  alias CartographBackend.Accounts.User
  alias CartographBackend.Repo
  alias CartographBackendWeb.SessionToken

  setup do
    user =
      %User{}
      |> User.changeset(%{name: "Agente", email: "agente@example.com", password: "secret123"})
      |> Repo.insert!()

    %{user: user}
  end

  test "a token works until its session is revoked", %{conn: conn, user: user} do
    conn = authenticate(conn, user)

    assert json_response(get(conn, ~p"/api/auth/me"), 200)["email"] == user.email

    assert json_response(post(conn, ~p"/api/auth/logout"), 200)["ok"]

    # Same token, now refused: the signature is still valid, the session is not.
    assert get(build_conn() |> copy_auth(conn), ~p"/api/auth/me").status == 401
  end

  test "changing the password ends every session", %{user: user} do
    first = authenticate(build_conn(), user)
    second = authenticate(build_conn(), user)

    assert get(first, ~p"/api/auth/me").status == 200
    assert get(second, ~p"/api/auth/me").status == 200

    {:ok, _} = Accounts.update_user(user.id, %{"password" => "a brand new one"})

    assert get(first, ~p"/api/auth/me").status == 401
    assert get(second, ~p"/api/auth/me").status == 401
  end

  test "changing something other than the password leaves sessions alone", %{user: user} do
    conn = authenticate(build_conn(), user)

    {:ok, _} = Accounts.update_user(user.id, %{"name" => "Outro Nome"})

    assert get(conn, ~p"/api/auth/me").status == 200
  end

  test "a token in the pre-session format is refused", %{conn: conn, user: user} do
    legacy = Phoenix.Token.sign(CartographBackendWeb.Endpoint, "user auth", user.id)

    conn = put_req_header(conn, "authorization", "Bearer #{legacy}")

    assert get(conn, ~p"/api/auth/me").status == 401
  end

  test "a token naming a session that never existed is refused", %{conn: conn, user: user} do
    forged = SessionToken.sign(user.id, "not-a-real-session")

    conn = put_req_header(conn, "authorization", "Bearer #{forged}")

    assert get(conn, ~p"/api/auth/me").status == 401
  end

  test "one user's session id does not work for another user", %{conn: conn, user: user} do
    other =
      %User{}
      |> User.changeset(%{name: "Outro", email: "outro@example.com", password: "secret123"})
      |> Repo.insert!()

    {:ok, jti} = Accounts.open_session(other.id)
    crossed = SessionToken.sign(user.id, jti)

    conn = put_req_header(conn, "authorization", "Bearer #{crossed}")

    assert get(conn, ~p"/api/auth/me").status == 401
  end

  defp copy_auth(conn, from) do
    [auth] = Plug.Conn.get_req_header(from, "authorization")
    put_req_header(conn, "authorization", auth)
  end
end
