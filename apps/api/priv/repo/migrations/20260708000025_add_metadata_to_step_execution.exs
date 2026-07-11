defmodule CartographBackend.Repo.Migrations.AddMetadataToStepExecution do
  use Ecto.Migration

  def change do
    alter table(:step_execution) do
      # Generic per-step telemetry written by step implementations (e.g. the
      # agent step records token usage under the "agent" key). A jsonb map so
      # future steps can attach their own data without further migrations.
      add :metadata, :map, null: false, default: %{}
    end
  end
end
