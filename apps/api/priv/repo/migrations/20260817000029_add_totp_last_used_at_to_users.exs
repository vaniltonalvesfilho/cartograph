defmodule CartographBackend.Repo.Migrations.AddTotpLastUsedAtToUsers do
  use Ecto.Migration

  def change do
    alter table(:users) do
      # The time step of the last TOTP code accepted for this user, so the same
      # code cannot be replayed within its 30-second window.
      add :totp_last_used_at, :utc_datetime
    end
  end
end
