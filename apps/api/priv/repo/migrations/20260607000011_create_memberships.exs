defmodule CartographBackend.Repo.Migrations.CreateMemberships do
  use Ecto.Migration

  def change do
    create table(:memberships) do
      add :user_id, references(:users, on_delete: :delete_all), null: false
      add :subject_type, :string, null: false
      add :subject_id, :bigint, null: false
      add :access_level, :integer, null: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create index(:memberships, [:user_id])
    create index(:memberships, [:subject_type, :subject_id])
    create unique_index(:memberships, [:user_id, :subject_type, :subject_id])
  end
end
