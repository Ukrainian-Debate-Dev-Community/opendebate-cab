defmodule OpendebateCab.MixProject do
  use Mix.Project

  # opendebate-cab: the club cabinet, the public site and the engine
  # client. Layering (deps point down only):
  #
  #   engine (Node, engine/) <- core <- cab <- public
  #
  # cab and core know nothing above them. The `full` release (the image)
  # runs cab (:4000) and public (:4001) in one node; `cab` runs the
  # cabinet alone.
  def project do
    [
      apps_path: "apps",
      version: "0.4.0",
      start_permanent: Mix.env() == :prod,
      listeners: [Phoenix.CodeReloader],
      deps: [],
      releases: releases()
    ]
  end

  defp releases do
    [
      full: [
        applications: [cab: :permanent, public: :permanent]
      ],
      cab: [
        applications: [cab: :permanent]
      ]
    ]
  end
end
