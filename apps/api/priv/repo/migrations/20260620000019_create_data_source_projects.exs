defmodule CartographBackend.Repo.Migrations.CreateDataSourceProjects do
  use Ecto.Migration

  def change do
    create table(:data_source_projects, primary_key: false) do
      add :data_source_id, references(:data_sources, on_delete: :delete_all), null: false
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      timestamps()
    end

    create unique_index(:data_source_projects, [:data_source_id, :project_id])
    create index(:data_source_projects, [:project_id])
  end
end
