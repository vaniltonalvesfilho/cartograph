defmodule CartographBackend.Accounts.ApiToken do
  use Ecto.Schema
  import Ecto.Changeset

  schema "api_tokens" do
    field :name,         :string
    field :token_hash,   :string
    field :prefix,       :string
    field :last_used_at, :utc_datetime
    field :expires_at,   :utc_datetime

    belongs_to :user, CartographBackend.Accounts.User

    timestamps(type: :utc_datetime)
  end

  def changeset(token, attrs) do
    token
    |> cast(attrs, [:name, :token_hash, :prefix, :user_id, :expires_at])
    |> validate_required([:name, :token_hash, :prefix, :user_id])
    |> validate_length(:name, min: 1, max: 100)
    |> unique_constraint(:token_hash)
  end
end
