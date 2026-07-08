defmodule CartographBackend.Repo.Migrations.CreateDataSources do
  use Ecto.Migration

  def change do
    create table(:data_sources) do
      add :name, :string, null: false
      add :slug, :string, null: false
      add :adapter, :string, null: false
      add :host, :string, null: false
      add :port, :integer, null: false
      add :database_name, :string, null: false
      add :username, :string, null: false
      add :password_encrypted, :binary
      add :ssl, :boolean, default: false, null: false
      add :notes, :text
      timestamps()
    end

    create unique_index(:data_sources, [:slug])
  end
end
