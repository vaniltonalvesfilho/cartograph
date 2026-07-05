defmodule CartographBackend.Repo.Migrations.CreateGroups do
  use Ecto.Migration

  def change do
    create table(:groups) do
      add :name, :string, null: false, size: 255
      add :parent_id, :bigint
      add :position, :integer, null: false, default: 0
      add :created_at, :utc_datetime_usec, null: false
    end

    create index(:groups, [:parent_id])

    execute(
      "ALTER TABLE groups ADD CONSTRAINT groups_parent_id_fkey FOREIGN KEY (parent_id) REFERENCES groups(id) ON DELETE CASCADE",
      "ALTER TABLE groups DROP CONSTRAINT groups_parent_id_fkey"
    )
  end
end
