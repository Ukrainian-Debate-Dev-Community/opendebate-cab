# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :cab,
  ecto_repos: [Cab.Repo],
  generators: [timestamp_type: :utc_datetime]

# Mail goes through Core.Mailer: kept in memory (and shown at
# /dev/mailbox) until runtime.exs points it at an SMTP server
config :swoosh, :api_client, false
config :core, Core.Mailer, adapter: Swoosh.Adapters.Local
config :cab, :mail_from, {"cab", "noreply@localhost"}

# cab's JSON API: requests per minute and burst, per signed-in account
# or per anonymous IP (runtime.exs reads RATE_LIMIT_* in production)
config :cab, CabWeb.RateLimit,
  enabled: true,
  signed_in: {60, 20},
  anonymous: {20, 20},
  trust_cf_ip: false

# Policy and Terms are the deployment's own documents, one folder per
# language (en/policy.md, en/terms.md, ...); cab only serves them.
# LEGAL_DIR (runtime.exs, also read from .env) points at them; without it
# development looks in an opendebate-server checkout next to this repo,
# and without the documents the pages answer 404
config :cab, :legal_dir, Path.expand("../../opendebate-server/legal", __DIR__)

# Configure the endpoint
# English by default; Ukrainian when the browser or the footer asks
config :cab, CabWeb.Gettext, default_locale: "en", locales: ~w(en uk)

config :cab, CabWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: CabWeb.ErrorHTML, json: CabWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: Cab.PubSub,
  live_view: [signing_salt: "ubjlL7er"]

# Configure LiveView
config :phoenix_live_view,
  # the attribute set on all root tags. Used for Phoenix.LiveView.ColocatedCSS.
  root_tag_attribute: "phx-r"

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  cab: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../apps/cab/assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.3.0",
  cab: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("../apps/cab", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [:request_id]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"

# OAuth sign-in providers. Google asks only for the basic scopes:
# the account's id, name, e-mail and picture.
config :ueberauth, Ueberauth,
  providers: [
    github: {Ueberauth.Strategy.Github, [default_scope: "read:user user:email"]},
    google: {Ueberauth.Strategy.Google, [default_scope: "openid email profile"]}
  ]
