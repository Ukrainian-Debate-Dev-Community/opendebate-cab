import Config

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

# standings cache: off in tests (global ETS would leak between tests
# that reuse engine event ids); the cache itself has a unit test
config :cab, :standings_cache, false
