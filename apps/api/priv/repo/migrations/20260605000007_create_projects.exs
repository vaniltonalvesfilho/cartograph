defmodule CartographBackend.Repo.Migrations.CreateProjects do
  use Ecto.Migration

  def change do
    create table(:projects) do
      add :name, :string, null: false, size: 255
      add :group_id, references(:groups, on_delete: :nilify_all)
      add :position, :integer, null: false, default: 0
      add :created_at, :utc_datetime_usec, null: false
    end

    create index(:projects, [:group_id])
  end
end
