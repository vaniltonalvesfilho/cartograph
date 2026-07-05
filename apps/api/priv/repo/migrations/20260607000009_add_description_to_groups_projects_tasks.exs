defmodule CartographBackend.Repo.Migrations.AddDescriptionToGroupsProjectsTasks do
  use Ecto.Migration

  def change do
    alter table(:groups) do
      add :description, :text
    end

    alter table(:projects) do
      add :description, :text
    end

    alter table(:task_definition) do
      add :description, :text
    end
  end
end
