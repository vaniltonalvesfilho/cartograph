defmodule CartographBackend.Repo.Migrations.AddUpdatedAtToGroupsProjectsTasks do
  use Ecto.Migration

  def change do
    alter table(:groups) do
      add :updated_at, :utc_datetime_usec
    end

    alter table(:projects) do
      add :updated_at, :utc_datetime_usec
    end

    alter table(:task_definition) do
      add :updated_at, :utc_datetime_usec
    end
  end
end
