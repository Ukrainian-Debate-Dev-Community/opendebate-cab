defmodule Platform.MixProject do
  use Mix.Project

  # Umbrella of the uadebate platform. Layering (deps point down only):
  #
  #   engine (Node, cab/api) <- core <- cab <- uadebate
  #                                      ^------- dfu
  #
  # Releases pick the scope: a deployment that wants only cab ships
  # `cab_only` and never compiles-in uadebate/dfu.
  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      deps: [],
      releases: releases()
    ]
  end

  defp releases do
    [
      cab_only: [
        applications: [cab: :permanent]
      ],
      full: [
        applications: [cab: :permanent, uadebate: :permanent, dfu: :permanent]
      ]
    ]
  end
end
