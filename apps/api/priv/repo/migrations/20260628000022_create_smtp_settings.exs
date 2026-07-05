defmodule CartographBackend.Repo.Migrations.CreateSmtpSettings do
  use Ecto.Migration

  def change do
    create table(:smtp_settings) do
      add :host,               :string,  null: false
      add :port,               :integer, null: false, default: 587
      add :username,           :string
      add :password_encrypted, :binary
      add :from_name,          :string
      add :from_email,         :string,  null: false
      add :tls,                :string,  null: false, default: "if_available"
      add :auth,               :boolean, null: false, default: true
      add :enabled,            :boolean, null: false, default: false
      timestamps()
    end
  end
end
