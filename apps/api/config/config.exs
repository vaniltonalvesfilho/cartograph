# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :cartograph_backend,
  ecto_repos: [CartographBackend.Repo],
  generators: [timestamp_type: :utc_datetime]

# Configure the endpoint
config :cartograph_backend, CartographBackendWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [json: CartographBackendWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: CartographBackend.PubSub,
  live_view: [signing_salt: "Izf/OJdK"]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Mailer (Swoosh). The SMTP relay is configured at runtime from the database
# (see CartographBackend.Mailing), so only the adapter is fixed here. We disable
# the HTTP api_client because the SMTP adapter (gen_smtp) does not need it.
config :cartograph_backend, CartographBackend.Mailer, adapter: Swoosh.Adapters.SMTP
config :swoosh, :api_client, false

# Browser origins allowed for CORS and the WebSocket origin check.
# localhost:4200 = Angular dev server; app://cartograph = Electron client.
# Production overrides this from ALLOWED_ORIGINS in config/runtime.exs.
config :cartograph_backend, :allowed_origins, ["http://localhost:4200", "app://cartograph"]

# Signing salt for the session cookie. This dev value is not a secret; a
# release must set SESSION_SIGNING_SALT (see config/runtime.exs).
config :cartograph_backend, :session_signing_salt, "dev-only-session-salt"

# Ceiling on the cost Absinthe will accept for one GraphQL document, scored
# before resolution. Generous for the dashboard's own queries; low enough that
# a deeply nested document cannot be used to pin the database.
config :cartograph_backend, :graphql_max_complexity, 200

# Throttling for the unauthenticated credential endpoints. `{limit, window_ms}`
# per key: `address` is the calling host, `identifier` is the account being
# attempted (the email, or the pending 2FA session).
#
# The address budget is loose enough for a whole office behind one NAT; the
# identifier budget is what actually stops guessing. 5 tries per 15 minutes
# against a 6-digit code is roughly 1 in 2000 odds of a hit over a year of
# sustained attempts.
config :cartograph_backend, CartographBackendWeb.Plugs.RateLimit,
  login: [address: {60, :timer.minutes(15)}, identifier: {10, :timer.minutes(15)}],
  totp: [address: {60, :timer.minutes(15)}, identifier: {5, :timer.minutes(15)}]

# Oban
config :cartograph_backend, Oban,
  engine: Oban.Engines.Basic,
  repo: CartographBackend.Repo,
  queues: [executions: 4]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
