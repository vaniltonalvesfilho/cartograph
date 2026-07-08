defmodule CartographBackend.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users) do
      add :name, :string, null: false, size: 255
      add :email, :string, null: false, size: 255
      add :password_hash, :string, null: false
      add :is_admin, :boolean, null: false, default: false
      add :inserted_at, :utc_datetime_usec, null: false
    end

    create unique_index(:users, [:email])
  end
end
