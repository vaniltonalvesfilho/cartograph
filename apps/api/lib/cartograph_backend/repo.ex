defmodule CartographBackend.Repo do
  use Ecto.Repo,
    otp_app: :cartograph_backend,
    adapter: Ecto.Adapters.Postgres
end
