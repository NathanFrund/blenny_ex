import Config

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :blenny_example_app, BlennyExampleAppWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "qkx3X7BKk6w3mS/oYrWk6ClAnVfXQ0gwhjs8HSkRIfCSVMqDPgD1P70JL2R6QUnr",
  server: false

# In test we don't send emails
config :blenny_example_app, BlennyExampleApp.Mailer, adapter: Swoosh.Adapters.Test

# Disable swoosh api client as it is only required for production adapters
config :swoosh, :api_client, false

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

# Use original FormAuth (InMemory) in test env — it has no external deps
config :blenny_ex,
  modules: [
    BlennyExampleApp.Blenny.FormAuth,
    BlennyExampleApp.Blenny.DashboardModule
  ]
