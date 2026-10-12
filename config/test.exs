import Config

config :core, Core.Mailer, adapter: Swoosh.Adapters.Test

config :cab, :legal_dir, Path.expand("../apps/cab/test/support/legal", __DIR__)

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :cab, Cab.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "cab_gateway_test#{System.get_env("MIX_TEST_PARTITION")}",
  port: 5432,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :uadebate, Uadebate.Repo,
  username: "postgres",
  password: "postgres",
  hostname: "localhost",
  database: "uadebate_test#{System.get_env("MIX_TEST_PARTITION")}",
  port: 5432,
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

config :uadebate, :uploads_dir, Path.join(System.tmp_dir!(), "uadebate-uploads-test")

config :uadebate, UadebateWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4003],
  secret_key_base: "Tz8mK2vQ5nB1xR7cL4wH9dF3jS6pA0gE2uY5kN8tM1qV4zC7bX0rD3fG6hJ9wP2s",
  server: false

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :cab, CabWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "pcTGx24RetJ4w8tsy07/57TzZuynVVvB3y+aJ3jBYkW6951u7HKhCf0RX044fX0O",
  server: false

# Stub the Node engine at the HTTP boundary (Req.Test); no live engine
# is required in tests.
config :core, Core.Engine,
  base_url: "http://engine.test",
  jwt_secret: "test-engine-secret",
  req_options: [plug: {Req.Test, Core.Engine}]

config :cab, :portal_api_token, "portal-test-token"

# Print only warnings and errors during test
config :logger, level: :warning

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true

# no API rate limit while developing or testing (the walkthrough and the
# stress test run far faster on purpose); tests turn it on where needed
config :cab, CabWeb.RateLimit, enabled: false
