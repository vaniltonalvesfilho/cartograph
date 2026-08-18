defmodule CartographBackend.Accounts.UserSession do
  @moduledoc """
  One logged-in session.

  The bearer token the dashboard holds is a `Phoenix.Token`, which is signed
  rather than stored — so on its own it stays valid until it expires and there
  is no way to cut it short. Each token now carries the `jti` of a row here, so
  a session can be ended on the server: on sign-out, on a password change, or
  by an admin dealing with a lost laptop.
  """
  use Ecto.Schema
  import Ecto.Changeset

  schema "user_sessions" do
    field :jti, :string
    field :revoked_at, :utc_datetime
    field :last_used_at, :utc_datetime
    field :inserted_at, :utc_datetime_usec

    belongs_to :user, CartographBackend.Accounts.User
  end

  def changeset(session, attrs) do
    session
    |> cast(attrs, [:user_id, :jti, :revoked_at, :last_used_at])
    |> validate_required([:user_id, :jti])
    |> put_inserted_at()
    |> unique_constraint(:jti)
  end

  defp put_inserted_at(%{data: %{id: nil}} = cs),
    do: put_change(cs, :inserted_at, DateTime.utc_now())

  defp put_inserted_at(cs), do: cs
end
