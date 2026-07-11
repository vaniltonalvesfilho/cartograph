import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :cartograph_backend, CartographBackend.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "cartograph_backend_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :cartograph_backend, CartographBackendWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "HwQOWh65xwgugNcqJfKpyamZLSxAqPrBho0JJv5Xo3FHm9/NtjyarX8qryuXQ9rP",
  server: false

# The agent step must never call api.anthropic.com from the test suite —
# every test (and QA/E2E run) goes through the fake client.
config :cartograph_backend, :anthropic_client, CartographBackend.Agents.AnthropicClientFake

# No queues, plugins or staging in tests. Otherwise the Stager polls every
# second, fails to check a connection out of the SQL sandbox, and crashes;
# enough of those restarts within one run takes the Repo down with it and
# unrelated tests start failing with "Repo not started". (This is what Oban's
# `testing: :manual` sets, spelled out — that option also demands the Oban
# schema be migrated to the latest version, which the test DB is not.)
config :cartograph_backend, Oban,
  queues: false,
  plugins: false,
  stage_interval: :infinity

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
