defmodule OpendebateCab.MixProject do
  use Mix.Project

  # opendebate-cab: the club cabinet and its engine client. Layering
  # (deps point down only):
  #
  #   engine (Node, engine/) <- core <- cab
  #
  # Apps built on top of cab pull this repo in and depend on apps/cab
  # and apps/core; cab and core know nothing above them.
  def project do
    [
      apps_path: "apps",
      version: "0.2.2",
      start_permanent: Mix.env() == :prod,
      listeners: [Phoenix.CodeReloader],
      deps: [],
      releases: releases()
    ]
  end

  defp releases do
    [
      cab: [
        applications: [cab: :permanent]
      ]
    ]
  end
end
