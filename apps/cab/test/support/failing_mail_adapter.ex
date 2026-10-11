defmodule Cab.FailingMailAdapter do
  @moduledoc "A mail adapter that always refuses, to test what a head sees when sending fails."
  use Swoosh.Adapter

  @impl true
  def deliver(_email, _config), do: {:error, :unreachable}
end
