defmodule CartographBackend.Repo.Migrations.AddTriggerToTaskExecution do
  use Ecto.Migration

  def change do
    alter table(:task_execution) do
      # How the execution was started: "manual" (user-triggered) or "cron"
      # (scheduled). Existing rows are backfilled as manual via the default.
      add :trigger, :string, null: false, default: "manual"
    end
  end
end
