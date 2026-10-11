defmodule CabWeb.OwnerHTML do
  @moduledoc """
  The owner tree's pages: the club edit page, the members page and the
  owner session page (registration, signups, the allocator / rooms).
  """
  use CabWeb, :html

  import CabWeb.MemberHTML, only: [archive_section: 1]

  embed_templates "owner_html/*"

  # template helpers

  # the allocator's people: participant id => %{id, name}
  defp people(signups) do
    Map.new(signups, fn participant ->
      {participant["id"], %{id: participant["id"], name: participant["display_name"]}}
    end)
  end

  defp guest_link(%{"id" => participant_id}, links),
    do: Enum.find(links, &(&1.engine_participant_id == participant_id))

  defp person_kind(participant, links, members, invitations) do
    cond do
      Map.has_key?(invitations, participant["id"]) -> gettext("invited, not accepted yet")
      guest_link(participant, links) -> gettext("guest")
      Enum.any?(members, &(&1.user.node_user_id == participant["user_id"])) -> gettext("member")
      true -> gettext("signed-in user")
    end
  end

  # a membership role, as the members table writes it
  defp role_word("head"), do: gettext("head")
  defp role_word("member"), do: gettext("member")
  defp role_word(other), do: other

  defp seat_side("og"), do: gettext("OG")
  defp seat_side("oo"), do: gettext("OO")
  defp seat_side("cg"), do: gettext("CG")
  defp seat_side("co"), do: gettext("CO")

  # where the person sits: the draft before rooms exist, the rooms after
  defp seat_words(participant, %{rooms: rooms}, _draft) when rooms != [] do
    Enum.find_value(rooms, gettext("waiting"), fn room ->
      cond do
        Enum.any?(room["RoomAdjudicators"] || [], &seat_of?(&1, participant)) ->
          gettext("%{room} adjudicator", room: room_label(room))

        team =
            Enum.find(
              room["RoomTeams"] || [],
              &Enum.any?(&1["RoomSpeakers"] || [], fn s -> seat_of?(s, participant) end)
            ) ->
          gettext("%{room} %{side}", room: room_label(room), side: side_code(team["position"]))

        true ->
          nil
      end
    end)
  end

  defp seat_words(participant, _state, draft) do
    case Enum.find(draft, fn {_key, pid} -> pid == participant["id"] end) do
      {key, _pid} ->
        case String.split(key, ":") do
          [room, "judge"] -> gettext("%{room} adjudicator", room: "R#{room}")
          [room, side, _n] -> gettext("%{room} %{side}", room: "R#{room}", side: seat_side(side))
        end

      nil ->
        gettext("waiting")
    end
  end

  defp seat_of?(seat, participant) do
    (get_in(seat, ["EventParticipant", "id"]) || seat["participant_id"]) == participant["id"]
  end

  defp removable?(_participant, %{stage: :done}), do: false

  defp removable?(participant, %{rooms: rooms}),
    do: not MapSet.member?(Cab.Sessions.seated_ids(rooms), participant["id"])

  defp signed_up_counts(signups) do
    people = length(signups)
    ngettext("%{count} person", "%{count} people", people)
  end

  defp attendance_line(signups) do
    rooms = Cab.Sessions.room_count(signups)

    ngettext(
      "%{people} checked in, %{count} room.",
      "%{people} checked in, %{count} rooms.",
      rooms,
      people: signed_up_counts(signups)
    )
  end

  defp deletable_rooms?(%{stage: :running, rooms: rooms}) when rooms != [],
    do: Enum.all?(rooms, &(&1["status"] == "pending"))

  defp deletable_rooms?(_state), do: false

  # an address no account uses: the guest gets a name, the link goes out by hand
  defp email_only?(query, %{users: []}),
    do: String.match?(String.trim(query), ~r/^[^@\s]+@[^@\s]+\.[^@\s]+$/)

  defp email_only?(_query, _suggestions), do: false
end
