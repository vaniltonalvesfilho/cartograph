defmodule CartographBackend.Repo.Migrations.AddProjectIdToTaskDefinition do
  use Ecto.Migration

  def change do
    alter table(:task_definition) do
      add :project_id, :bigint
    end

    create index(:task_definition, [:project_id])
  end
end
