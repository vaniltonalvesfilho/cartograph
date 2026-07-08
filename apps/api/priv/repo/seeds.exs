# Script for populating the database. You can run it as:
#
#     mix run priv/repo/seeds.exs
#
# Inside the script, you can read and write to any of your
# repositories directly:
#
#     CartographBackend.Repo.insert!(%CartographBackend.SomeSchema{})
#
# We recommend using the bang functions (`insert!`, `update!`
# and so on) as they will fail if something goes wrong.

alias CartographBackend.Accounts

# Random password generated per setup (hex-encoded random bytes → hash-like token).
# Printed once at creation; the stored value is Bcrypt-hashed and not recoverable.
password = 16 |> :crypto.strong_rand_bytes() |> Base.encode16(case: :lower)

case Accounts.admin_create_user(%{
       "name" => "Admin",
       "email" => "admin@cartograph.local",
       "password" => password,
       "is_admin" => true
     }) do
  {:ok, u} ->
    IO.puts("""

    ┌──────────────────────────────────────────────────────────────┐
    │  Admin created — SAVE THE PASSWORD (it is not recoverable)    │
    ├──────────────────────────────────────────────────────────────┤
      email:    #{u.email}
      password: #{password}

      Change the password on first login.
    └──────────────────────────────────────────────────────────────┘
    """)

  {:error, _} ->
    IO.puts(
      "Admin already exists — password unchanged. " <>
        "Run `make db.reset` to recreate from scratch with a new password."
    )
end
