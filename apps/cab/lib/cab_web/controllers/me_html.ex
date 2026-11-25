defmodule CabWeb.MeHTML do
  @moduledoc """
  /me - profile, invitations, my clubs and schedule, engine stats
  verbatim, history; and a member's saved answers for one club.
  """
  use CabWeb, :html

  import Ui.FormComponents,
    only: [
      answer_name: 1,
      block_type: 1,
      field_label: 1,
      input_type: 1,
      placeholder: 1,
      prompt: 1
    ]

  embed_templates "me_html/*"

  # the user's part in a seat: the chair, or their side and roles in
  # speaking order (an iron's several)
  defp seat_words(%{role: :chair}, _user), do: gettext("You adjudicate this room.")

  defp seat_words(%{role: :speaker, room_team: room_team, session: session} = seat, _user) do
    side = Cab.Format.side(Cab.Format.of(session), room_team["position"])

    roles =
      room_team
      |> room_speakers()
      |> Enum.with_index()
      |> Enum.filter(fn {speaker, _i} ->
        get_in(speaker, ["EventParticipant", "id"]) in seat.participant_ids
      end)
      |> Enum.map_join(", ", fn {_speaker, i} ->
        CabWeb.BallotForm.role_label(Enum.at(CabWeb.BallotForm.roles(side), i) || "")
      end)

    gettext("You speak for %{side}: %{roles}.", side: side_short(side), roles: roles)
  end

  # the Next session column, written out as words - no pills anywhere
  defp tonight_words(nil), do: gettext("quiet")

  defp tonight_words({session, :signup, _rooms}) do
    if Cab.Sessions.full?(session),
      do: gettext("registration full"),
      else: gettext("registration open")
  end

  defp tonight_words({_session, :closed, _rooms}), do: gettext("registration closed")

  defp tonight_words({_session, :running, _rooms}), do: gettext("running")

  # engine numbers shown with fixed decimals, as the engine once sent them
  defp fixed(value, decimals) when is_number(value),
    do: :erlang.float_to_binary(value / 1, decimals: decimals)

  defp fixed(value, _decimals), do: value

  # a role as people read it: club roles and session roles
  defp role_word("head"), do: gettext("head")
  defp role_word("member"), do: gettext("member")
  defp role_word("speaker"), do: gettext("speaker")
  defp role_word("adjudicator"), do: gettext("adjudicator")
  defp role_word(other), do: other
end
