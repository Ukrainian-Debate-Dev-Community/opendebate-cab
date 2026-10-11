defmodule Core.MixProject do
  use Mix.Project

  # L0 of the umbrella: shared kernel. Depends on no other app -
  # engine HTTP client, auth/JWT primitives, design-system UI
  # components. Everything above (cab, uadebate, dfu) may depend on
  # core; core may depend on nothing above it.
  def project do
    [
      app: :core,
      version: "0.1.0",
      build_path: "../../_build",
      config_path: "../../config/config.exs",
      deps_path: "../../deps",
      lockfile: "../../mix.lock",
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger]
    ]
  end

  defp deps do
    [
      {:req, "~> 0.5"},
      {:joken, "~> 2.6"},
      {:jason, "~> 1.2"},
      {:phoenix_live_view, "~> 1.2.0"},
      {:plug, "~> 1.14", only: :test}
    ]
  end
end
