defmodule CartographBackend.Repo.Migrations.CreateStepExecutions do
  use Ecto.Migration

  def change do
    create table(:step_execution) do
      add :execution_id, :bigint, null: false
      add :step_name, :string, null: false
      add :step_order, :integer, null: false
      add :status, :string, null: false, default: "PENDING"
      add :started_at, :utc_datetime_usec
      add :finished_at, :utc_datetime_usec
      add :error_message, :text
    end

    create index(:step_execution, [:execution_id])
  end
end
