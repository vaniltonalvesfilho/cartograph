defmodule CartographBackend.Repo.Migrations.CreateTaskDefinitions do
  use Ecto.Migration

  def change do
    create table(:task_definition) do
      add :name, :string, null: false
      add :dsl, :text, null: false
      add :cron, :string
      add :created_at, :utc_datetime_usec, null: false
    end
  end
end
