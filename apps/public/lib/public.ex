defmodule Public do
  @moduledoc """
  The public site of the organisation running the platform, at the top. It keeps
  its own news, calendar and content-manager roles, and reads the other
  services downward: clubs and accounts from cab. Dependencies point
  down (public -> cab -> core); the organisation's own texts come from
  its tenant folder (Public.Tenant).
  """

  @doc "Tournaments feed for the portal (calendar / front page)."
  defdelegate tournaments(params \\ []), to: Cab.EngineApi, as: :list_public_events
end
