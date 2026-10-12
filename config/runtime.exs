import Config

# In dev, load the repo root's .env into the environment ourselves: `source
# .env` only creates shell variables, it does not export them to the
# mix process. The path is fixed to the umbrella root so mix tasks run
# from an app directory find it too. Exported variables still win.
dotenv = Path.expand("../.env", __DIR__)

if config_env() == :dev and File.exists?(dotenv) do
  for line <- File.stream!(dotenv),
      line = String.trim(line),
      line != "" and not String.starts_with?(line, "#"),
      [key, value] = String.split(line, "=", parts: 2),
      System.get_env(key) == nil do
    System.put_env(key, String.trim(value, "\""))
  end
end

config :ueberauth, Ueberauth.Strategy.Github.OAuth,
  client_id: System.get_env("GITHUB_CLIENT_ID"),
  client_secret: System.get_env("GITHUB_CLIENT_SECRET")

config :ueberauth, Ueberauth.Strategy.Google.OAuth,
  client_id: System.get_env("GOOGLE_CLIENT_ID"),
  client_secret: System.get_env("GOOGLE_CLIENT_SECRET")

# Node engine + portal API. Test config pins its own deterministic
# values in config/test.exs; runtime.exs runs after it, so skip :test.
# The engine trusts any token signed with this secret (admin included),
# so production refuses to boot without a real one.
if config_env() != :test do
  engine_secret =
    case {config_env(), System.get_env("ENGINE_JWT_SECRET")} do
      {:prod, secret} when secret in [nil, ""] ->
        raise "ENGINE_JWT_SECRET is missing; the engine would trust a public default"

      {:prod, "insecure-dev-engine-secret"} ->
        raise "ENGINE_JWT_SECRET is the public dev default; set a real secret"

      {_env, nil} ->
        "insecure-dev-engine-secret"

      {_env, secret} ->
        secret
    end

  config :core, Core.Engine,
    base_url: System.get_env("ENGINE_URL", "http://localhost:3100"),
    jwt_secret: engine_secret

  if legal_dir = System.get_env("LEGAL_DIR") do
    config :cab, :legal_dir, legal_dir
  end
end

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

# ## Using releases
#
# If you use `mix release`, you need to explicitly enable the server
# by passing the PHX_SERVER=true when you start it:
#
#     PHX_SERVER=true bin/cab start
#
# Alternatively, you can use `mix phx.gen.release` to generate a `bin/server`
# script that automatically sets the env var above.
if System.get_env("PHX_SERVER") do
  config :cab, CabWeb.Endpoint, server: true
end

config :cab, CabWeb.Endpoint, http: [port: String.to_integer(System.get_env("PORT", "4000"))]

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :cab, CabWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$",
        # Gettext translations
        ~r"priv/gettext/.*\.po$",
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/cab_web/router\.ex$",
        ~r"lib/cab_web/(controllers|live|components)/.*\.(ex|heex)$"
      ]
    ]
end

if config_env() == :prod do
  # the JSON API's rate limit: behind Cloudflare the visitor's address is
  # CF-Connecting-IP (the firewall admits only Cloudflare)
  per_minute = fn name, default -> String.to_integer(System.get_env(name, default)) end

  config :cab, CabWeb.RateLimit,
    enabled: System.get_env("RATE_LIMIT_ENABLED", "true") == "true",
    signed_in: {per_minute.("RATE_LIMIT_SIGNED_IN", "60"), 20},
    anonymous: {per_minute.("RATE_LIMIT_ANONYMOUS", "20"), 20},
    trust_cf_ip: true

  database_url =
    System.get_env("DATABASE_URL") ||
      raise """
      environment variable DATABASE_URL is missing.
      For example: ecto://USER:PASS@HOST/DATABASE
      """

  maybe_ipv6 = if System.get_env("ECTO_IPV6") in ~w(true 1), do: [:inet6], else: []

  config :cab, Cab.Repo,
    # ssl: true,
    url: database_url,
    pool_size: String.to_integer(System.get_env("POOL_SIZE") || "10"),
    # For machines with several cores, consider starting multiple pools of `pool_size`
    # pool_count: 4,
    socket_options: maybe_ipv6

  # The secret key base is used to sign/encrypt cookies and other secrets.
  # A default value is used in config/dev.exs and config/test.exs but you
  # want to use a different value for prod and you most likely don't want
  # to check this value into version control, so we use an environment
  # variable instead.
  secret_key_base =
    System.get_env("SECRET_KEY_BASE") ||
      raise """
      environment variable SECRET_KEY_BASE is missing.
      You can generate one by calling: mix phx.gen.secret
      """

  host = System.get_env("PHX_HOST") || "example.com"

  # Mail: SMTP when SMTP_HOST is set, otherwise kept in memory (nothing
  # leaves the server). MAIL_FROM is "Name <address>".
  if smtp_host = System.get_env("SMTP_HOST") do
    config :core, Core.Mailer,
      adapter: Swoosh.Adapters.SMTP,
      relay: smtp_host,
      port: String.to_integer(System.get_env("SMTP_PORT", "587")),
      username: System.get_env("SMTP_USERNAME"),
      password: System.get_env("SMTP_PASSWORD"),
      tls: :always,
      # gen_smtp verifies nothing on its own: without the system CAs and
      # the server name the STARTTLS handshake fails
      tls_options: [
        verify: :verify_peer,
        cacerts: :public_key.cacerts_get(),
        server_name_indication: String.to_charlist(smtp_host),
        depth: 99,
        customize_hostname_check: [
          match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
        ]
      ],
      auth: :always,
      ssl: false,
      retries: 1
  else
    IO.warn("SMTP_HOST is not set: e-mails are kept in memory and never sent", [])
  end

  # Share the sign-in with sibling sites: SESSION_COOKIE_DOMAIN=".example.org"
  # lets every *.example.org host read cab's session cookie (read only).
  # Unset, the cookie stays on cab's own host.
  if domain = System.get_env("SESSION_COOKIE_DOMAIN") do
    config :cab, :session_cookie_domain, domain
  end

  case Regex.run(~r/^\s*(.*?)\s*<([^>]+)>\s*$/, System.get_env("MAIL_FROM", "")) do
    [_, name, address] -> config :cab, :mail_from, {name, address}
    _ -> :ok
  end

  config :cab, :dns_cluster_query, System.get_env("DNS_CLUSTER_QUERY")

  config :cab, CabWeb.Endpoint,
    url: [host: host, port: 443, scheme: "https"],
    http: [
      # Enable IPv6 and bind on all interfaces.
      # Set it to  {0, 0, 0, 0, 0, 0, 0, 1} for local network only access.
      # See the documentation on https://bandit.hexdocs.pm/Bandit.html#t:options/0
      # for details about using IPv6 vs IPv4 and loopback vs public addresses.
      ip: {0, 0, 0, 0, 0, 0, 0, 0}
    ],
    secret_key_base: secret_key_base

  # ## SSL Support
  #
  # To get SSL working, you will need to add the `https` key
  # to your endpoint configuration:
  #
  #     config :cab, CabWeb.Endpoint,
  #       https: [
  #         ...,
  #         port: 443,
  #         cipher_suite: :strong,
  #         keyfile: System.get_env("SOME_APP_SSL_KEY_PATH"),
  #         certfile: System.get_env("SOME_APP_SSL_CERT_PATH")
  #       ]
  #
  # The `cipher_suite` is set to `:strong` to support only the
  # latest and more secure SSL ciphers. This means old browsers
  # and clients may not be supported. You can set it to
  # `:compatible` for wider support.
  #
  # `:keyfile` and `:certfile` expect an absolute path to the key
  # and cert in disk or a relative path inside priv, for example
  # "priv/ssl/server.key". For all supported SSL configuration
  # options, see https://plug.hexdocs.pm/Plug.SSL.html#configure/1
  #
  # We also recommend setting `force_ssl` in your config/prod.exs,
  # ensuring no data is ever sent via http, always redirecting to https:
  #
  #     config :cab, CabWeb.Endpoint,
  #       force_ssl: [hsts: true]
  #
  # Check `Plug.SSL` for all available options in `force_ssl`.
end
