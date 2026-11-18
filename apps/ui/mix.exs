defmodule Ui.MixProject do
  use Mix.Project

  # The component library both web apps share (cab's cabinet and the
  # public site): tables, forms, banners, sections. A library, no
  # endpoint and no repo. It knows no app: whatever is an app's own (its
  # routes, its records, its words for them) the caller passes in.
  def project do
    [
      app: :ui,
      version: "0.4.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      # translation files list each text's file without a line number and
      # keep entries sorted, so branches rarely conflict in them
      gettext: [write_reference_line_numbers: false, sort_by_msgid: :case_sensitive]
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:core, in_umbrella: true},
      {:phoenix, "~> 1.8.13"},
      {:phoenix_html, "~> 4.1"},
      {:phoenix_live_view, "~> 1.2.0"},
      {:gettext, "~> 1.0"},
      {:lazy_html, ">= 0.1.0", only: :test}
    ]
  end
end
