defmodule CartographBackend.Repo.Migrations.CreateUserSessions do
  use Ecto.Migration

  def change do
    create table(:user_sessions) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      # Random id carried inside the signed session token, so a token can be
      # matched back to a row and revoked.
      add :jti, :string, null: false
      add :revoked_at, :utc_datetime
      add :last_used_at, :utc_datetime
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:user_sessions, [:jti])
    create index(:user_sessions, [:user_id])
  end
end
