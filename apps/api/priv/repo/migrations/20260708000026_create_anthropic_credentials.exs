defmodule CartographBackend.Repo.Migrations.CreateAnthropicCredentials do
  use Ecto.Migration

  def change do
    create table(:anthropic_credentials) do
      add :name, :string, null: false
      add :code, :string, null: false
      add :api_key_encrypted, :binary, null: false
      add :project_id, references(:projects, on_delete: :delete_all), null: false
      timestamps()
    end

    create unique_index(:anthropic_credentials, [:code])
    # Doubles as the FK index on project_id, same as slack_webhooks.
    create unique_index(:anthropic_credentials, [:project_id, :name])
  end
end
