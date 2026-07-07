defmodule CartographBackend.Repo.Migrations.CreateSlackWebhooks do
  use Ecto.Migration

  def change do
    create table(:slack_webhooks) do
      add :name,          :string, null: false
      add :code,          :string, null: false
      add :url_encrypted, :binary, null: false
      add :project_id,    references(:projects, on_delete: :delete_all), null: false
      timestamps()
    end

    create unique_index(:slack_webhooks, [:code])
    create unique_index(:slack_webhooks, [:project_id, :name])
  end
end
