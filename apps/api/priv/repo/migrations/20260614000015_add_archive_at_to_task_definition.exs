defmodule CartographBackend.Repo.Migrations.AddArchiveAtToTaskDefinition do
  use Ecto.Migration

  def change do
    alter table(:task_definition) do
      # Optional archive date/time: at or after this instant the job is
      # considered archived — no automatic (cron) runs are scheduled and manual
      # runs are refused. Complements release_at (the lower bound).
      add :archive_at, :utc_datetime_usec
    end
  end
end
