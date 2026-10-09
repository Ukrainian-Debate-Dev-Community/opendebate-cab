defmodule CabWeb.MeHTML do
  @moduledoc "/me — profile, invitations, my clubs and schedule, engine stats verbatim, history."
  use CabWeb, :html

  embed_templates "me_html/*"

  # the Next session column, written out as words — no pills anywhere
  defp tonight_words(nil), do: "quiet"

  defp tonight_words({_session, :signup, _rooms}), do: "registration open"

  defp tonight_words({_session, :closed, _rooms}), do: "registration closed"

  defp tonight_words({_session, :running, _rooms}), do: "running"
end
