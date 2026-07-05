defmodule CartographBackend.Repo.Migrations.AddReleaseAtToTaskDefinition do
  use Ecto.Migration

  def change do
    alter table(:task_definition) do
      # Optional release date/time: when set, automatic (cron) execution only
      # begins at or after this instant. Manual runs are unaffected.
      add :release_at, :utc_datetime_usec
    end
  end
end
