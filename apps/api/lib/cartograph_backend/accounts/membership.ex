defmodule CartographBackend.Accounts.Membership do
  use Ecto.Schema
  import Ecto.Changeset

  @valid_types ~w(group project task)
  @valid_levels [10, 20, 30, 40, 50]

  schema "memberships" do
    belongs_to :user, CartographBackend.Accounts.User
    field :subject_type, :string
    field :subject_id,   :integer
    field :access_level, :integer
    field :inserted_at,  :utc_datetime_usec
  end

  def changeset(m, attrs) do
    m
    |> cast(attrs, [:user_id, :subject_type, :subject_id, :access_level])
    |> validate_required([:user_id, :subject_type, :subject_id, :access_level])
    |> validate_inclusion(:subject_type, @valid_types)
    |> validate_inclusion(:access_level, @valid_levels)
    |> unique_constraint([:user_id, :subject_type, :subject_id])
    |> put_inserted_at()
  end

  defp put_inserted_at(%{data: %{id: nil}} = cs),
    do: put_change(cs, :inserted_at, DateTime.utc_now())
  defp put_inserted_at(cs), do: cs
end
