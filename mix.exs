defmodule Platform.MixProject do
  use Mix.Project

  # Umbrella of the uadebate platform. Layering (deps point down only):
  #
  #   engine (Node, engine/) <- core <- cab <- dfu <- uadebate
  #
  # uadebate is the public facade at the top: it aggregates data from
  # cab (tournaments, clubs, motions) and dfu (public org documents).
  # Releases pick the scope: a deployment that wants only cab ships
  # `cab_only` and never compiles-in dfu/uadebate.
  def project do
    [
      apps_path: "apps",
      version: "0.1.0",
      start_permanent: Mix.env() == :prod,
      listeners: [Phoenix.CodeReloader],
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
        applications: [cab: :permanent, dfu: :permanent, uadebate: :permanent]
      ]
    ]
  end
end
