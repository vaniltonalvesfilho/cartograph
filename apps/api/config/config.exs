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

# Oban
config :cartograph_backend, Oban,
  engine: Oban.Engines.Basic,
  repo: CartographBackend.Repo,
  queues: [executions: 4]

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
