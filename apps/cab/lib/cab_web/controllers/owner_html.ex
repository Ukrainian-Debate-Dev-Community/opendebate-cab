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

  defp guest_link(%{"user_id" => node_id}, links) when is_integer(node_id) do
    Enum.find(links, &(&1.user.node_user_id == node_id))
  end

  defp guest_link(_participant, _links), do: nil

  defp person_kind(participant, links, members, invitations) do
    cond do
      Map.has_key?(invitations, participant["id"]) -> "invited, not accepted yet"
      guest_link(participant, links) -> "guest"
      Enum.any?(members, &(&1.user.node_user_id == participant["user_id"])) -> "member"
      true -> "signed-in user"
    end
  end

  @seat_sides %{"og" => "OG", "oo" => "OO", "cg" => "CG", "co" => "CO"}

  # where the person sits: the draft before rooms exist, the rooms after
  defp seat_words(participant, %{rooms: rooms}, _draft) when rooms != [] do
    Enum.find_value(rooms, "waitlist", fn room ->
      cond do
        Enum.any?(room["RoomAdjudicators"] || [], &seat_of?(&1, participant)) ->
          "#{room_label(room)} judge"

        team =
            Enum.find(
              room["RoomTeams"] || [],
              &Enum.any?(&1["RoomSpeakers"] || [], fn s -> seat_of?(s, participant) end)
            ) ->
          "#{room_label(room)} #{side_code(team["position"])}"

        true ->
          nil
      end
    end)
  end

  defp seat_words(participant, _state, draft) do
    case Enum.find(draft, fn {_key, pid} -> pid == participant["id"] end) do
      {key, _pid} ->
        case String.split(key, ":") do
          [room, "judge"] -> "R#{room} judge"
          [room, side, _n] -> "R#{room} #{@seat_sides[side]}"
        end

      nil ->
        "not placed"
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
    "#{people} #{if people == 1, do: "person", else: "people"}"
  end

  defp attendance_line(signups) do
    rooms = Cab.Sessions.room_count(signups)
    "#{signed_up_counts(signups)} checked in → #{rooms} room#{if rooms != 1, do: "s"}."
  end

  defp deletable_rooms?(%{stage: :running, rooms: rooms}) when rooms != [],
    do: Enum.all?(rooms, &(&1["status"] == "pending"))

  defp deletable_rooms?(_state), do: false

  defp open_rooms(%{stage: :running, rooms: rooms}),
    do: Enum.reject(rooms, &(&1["status"] in ["confirmed", "completed"]))

  defp open_rooms(_state), do: []
end
