defmodule CartographBackend.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :name,          :string
    field :email,         :string
    field :password,      :string, virtual: true
    field :password_hash, :string
    field :is_admin,      :boolean, default: false
    field :totp_secret,   :binary
    field :totp_enabled,  :boolean, default: false
    field :inserted_at,   :utc_datetime_usec
  end

  def changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :password])
    |> validate_required([:name, :email, :password])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> validate_length(:password, min: 6)
    |> unique_constraint(:email)
    |> put_password_hash()
    |> put_inserted_at()
  end

  def update_changeset(user, attrs) do
    user
    |> cast(attrs, [:name, :email, :password])
    |> validate_format(:email, ~r/^[^\s]+@[^\s]+$/)
    |> validate_length(:password, min: 6)
    |> unique_constraint(:email)
    |> maybe_put_password_hash()
  end

  @doc """
  Privileged: `is_admin` is only ever set through this changeset, never via the
  common casts — a self-service profile flow reusing `changeset/2` must not be
  able to grant admin. Accepts a changeset to compose with the common casts.
  """
  def admin_changeset(user_or_changeset, attrs) do
    cast(user_or_changeset, attrs, [:is_admin])
  end

  defp put_password_hash(%{valid?: true, changes: %{password: pw}} = cs),
    do: put_change(cs, :password_hash, Bcrypt.hash_pwd_salt(pw))
  defp put_password_hash(cs), do: cs

  defp maybe_put_password_hash(%{valid?: true, changes: %{password: pw}} = cs),
    do: put_change(cs, :password_hash, Bcrypt.hash_pwd_salt(pw))
  defp maybe_put_password_hash(cs), do: cs

  def totp_changeset(user, attrs) do
    user
    |> cast(attrs, [:totp_secret, :totp_enabled])
  end

  defp put_inserted_at(%{data: %{id: nil}} = cs),
    do: put_change(cs, :inserted_at, DateTime.utc_now())
  defp put_inserted_at(cs), do: cs
end
