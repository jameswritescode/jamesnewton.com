# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :newton, :scopes,
  user: [
    default: true,
    module: Newton.Accounts.Scope,
    assign_key: :current_scope,
    access_path: [:user, :id],
    schema_key: :user_id,
    schema_type: :id,
    schema_table: :users,
    test_data_fixture: Newton.AccountsFixtures,
    test_setup_helper: :register_and_log_in_user
  ]

config :newton,
  ecto_repos: [Newton.Repo],
  generators: [timestamp_type: :utc_datetime]

config :newton, :media_root, Path.expand("../priv/media", __DIR__)

# Configure the endpoint
config :newton, NewtonWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: NewtonWeb.ErrorHTML, json: NewtonWeb.ErrorJSON],
    root_layout: {NewtonWeb.Layouts, :root},
    layout: false
  ],
  pubsub_server: Newton.PubSub,
  live_view: [signing_salt: "12EI2dpQ"]

# Configure the mailer
#
# By default it uses the "Local" adapter which stores the emails
# locally. You can see the emails in your browser, at "/dev/mailbox".
#
# For production it's recommended to configure a different adapter
# at the `config/runtime.exs`.
config :newton, Newton.Mailer, adapter: Swoosh.Adapters.Local

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  newton: [
    args:
      ~w(js/app.js js/admin.js js/gibson.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  newton: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

config :newton, :webauthn, rp_id: "localhost", origin: "http://localhost:4000"

config :mdex_native, syntax_highlighter: :lumis

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
