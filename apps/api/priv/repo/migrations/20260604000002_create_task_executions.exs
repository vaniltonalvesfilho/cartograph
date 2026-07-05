defmodule CartographBackend.Repo.Migrations.CreateTaskExecutions do
  use Ecto.Migration

  def change do
    create table(:task_execution) do
      add :task_definition_id, :bigint, null: false
      add :task_name, :string, null: false
      add :status, :string, null: false, default: "PENDING"
      add :stop_requested, :boolean, null: false, default: false
      add :created_at, :utc_datetime_usec, null: false
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec
    end

    create index(:task_execution, [:task_definition_id])
    create index(:task_execution, [:status])
  end
end
