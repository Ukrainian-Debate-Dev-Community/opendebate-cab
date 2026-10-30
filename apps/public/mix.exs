defmodule Public.MixProject do
  use Mix.Project

  # The public site, at the top: generic, its organisation's texts and
  # map come from the tenant folder (Public.Tenant). It reads cab
  # downward (clubs, accounts, the session cookie) and keeps its own
  # news, events and content-manager roles; nothing depends on it.
  def project do
    [
      app: :public,
      version: "0.3.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.17",
      elixirc_paths: elixirc_paths(Mix.env()),
      start_permanent: Mix.env() == :prod,
      aliases: aliases(),
      deps: deps(),
      listeners: [Phoenix.CodeReloader],
      # translation files list each text's file without a line number and
      # keep entries sorted, so branches rarely conflict in them
      gettext: [write_reference_line_numbers: false, sort_by_msgid: :case_sensitive]
    ]
  end

  def application do
    [
      mod: {Public.Application, []},
      extra_applications: [:logger]
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  defp deps do
    [
      {:core, in_umbrella: true},
      {:cab, in_umbrella: true},
      {:phoenix, "~> 1.8.13"},
      {:phoenix_ecto, "~> 4.5"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.2.0"},
      {:ecto_sql, "~> 3.13"},
      {:postgrex, ">= 0.0.0"},
      {:gettext, "~> 1.0"},
      {:jason, "~> 1.2"},
      {:bandit, "~> 1.5"},
      {:mdex, "~> 0.14.2"},
      {:lazy_html, ">= 0.1.0", only: :test}
    ]
  end

  defp aliases do
    [
      "ecto.setup": ["ecto.create", "ecto.migrate"],
      "ecto.reset": ["ecto.drop", "ecto.setup"],
      # cab's database too: the site's tests read accounts and clubs there
      test: [
        "ecto.create --quiet -r Public.Repo -r Cab.Repo",
        "ecto.migrate --quiet -r Public.Repo -r Cab.Repo",
        "test"
      ]
    ]
  end
end
