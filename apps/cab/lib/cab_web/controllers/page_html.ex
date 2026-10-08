defmodule CabWeb.PageHTML do
  @moduledoc "The front page (directory or cabinet) and /privacy."
  use CabWeb, :html

  embed_templates "page_html/*"

  # the next-session when: scheduled time or tonight's date
  defp session_when(%{scheduled_at: %DateTime{} = at}), do: Calendar.strftime(at, "%a %H:%M")
  defp session_when(_session), do: "sign-ups open"

  # the Next session column, written out as words — no pills anywhere
  defp tonight_words(nil), do: "quiet"

  defp tonight_words({session, :signup, _rooms}) do
    case session.scheduled_at do
      %DateTime{} = at -> "sign-ups open, #{Calendar.strftime(at, "%a %H:%M")}"
      _ -> "sign-ups open"
    end
  end

  defp tonight_words({_session, :closed, _rooms}), do: "sign-ups closed"

  defp tonight_words({_session, :running, rooms}),
    do: "session running, #{rooms} room#{if rooms != 1, do: "s"}"
end
