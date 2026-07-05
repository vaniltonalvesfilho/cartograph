defmodule CartographBackend.Repo.Migrations.CreateExecutionLogs do
  use Ecto.Migration

  def change do
    create table(:execution_log) do
      add :execution_id, :bigint, null: false
      add :step_execution_id, :bigint
      add :level, :string, null: false
      add :message, :text, null: false
      add :timestamp, :utc_datetime_usec, null: false
    end

    create index(:execution_log, [:execution_id])
  end
end
