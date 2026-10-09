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

  # approved members not signed up tonight, as form options
  defp addable_members(members, signups) do
    signed = MapSet.new(signups, & &1["user_id"])

    for membership <- members,
        not MapSet.member?(signed, membership.user.node_user_id) do
      {membership.user.username, membership.user.username}
    end
  end

  defp guest_user_ids(links) do
    for link <- links, is_integer(link.user.node_user_id), into: MapSet.new() do
      link.user.node_user_id
    end
  end

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
