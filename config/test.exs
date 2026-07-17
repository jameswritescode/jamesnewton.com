import Config

# Only in tests, remove the complexity from the password hashing algorithm
config :bcrypt_elixir, :log_rounds, 1

# Keep test image writes out of the repo.
config :newton, :media_root, Path.join(System.tmp_dir!(), "newton_test_media")

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :newton, Newton.Repo,
  database: "newton_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :newton, NewtonWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "Wjv04Jn7nFUnpRS8pMSSLc9ECmNQiOu39cXc32jlGBVYF+5G26V/vZ0yL/4AIoAs",
  server: false

# In test we don't send emails
config :newton, Newton.Mailer, adapter: Swoosh.Adapters.Test

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

config :newton, :webauthn, rp_id: "localhost", origin: "http://localhost:4000"

config :newton, Newton.IndexNow, req_options: [plug: {Req.Test, Newton.IndexNow}]

# Phoenix's channel test transport is a 2-tuple with no String.Chars impl, so
# the Prometheus aggregator would log a tag-drop warning on every LiveView test
# connection. Drop those metric groups in test only.
config :newton, Newton.PromEx,
  drop_metrics_groups: [:phoenix_socket_event_metrics, :phoenix_channel_event_metrics]
