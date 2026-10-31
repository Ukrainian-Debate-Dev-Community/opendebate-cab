defmodule Public.Application do
  @moduledoc false
  use Application

  @impl true
  def start(_type, _args) do
    # the organisation's texts and map, read before anything serves a
    # page; a folder missing a key the site needs stops the boot here
    Public.Tenant.load!()

    if Application.get_env(:public, :hand_cab_operator, true), do: hand_cab_operator()

    children = [
      Public.Repo,
      PublicWeb.Endpoint
    ]

    Supervisor.start_link(children, strategy: :one_for_one, name: Public.Supervisor)
  end

  @doc "cab knows nothing above it: the site tells it who runs it."
  def hand_cab_operator, do: Application.put_env(:cab, :operator, PublicWeb.CabOperator)

  @impl true
  def config_change(changed, _new, removed) do
    PublicWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
