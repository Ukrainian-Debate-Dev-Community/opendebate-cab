defmodule CabWeb.SessionPageHTML do
  @moduledoc """
  The session page, the room page (both rendered by LiveViews) and the
  ballot page. One room URL for every viewer: identity picks what
  renders and which actions appear.
  """
  use CabWeb, :html

  # this module's ballot/1 is the ballot PAGE; the kit's ballot
  # component stays qualified as Ui.ballot
  import CabWeb.Ui, except: [ballot: 1]
  alias CabWeb.Ui

  embed_templates "session_page_html/*"

  # the prep clock: 15 minutes from the motion's publication — the
  # engine ships created_at (ISO) with the motion; absent = no clock
  defp prep_deadline(room) do
    with %{"created_at" => created} when is_binary(created) <- room["Motion"],
         {:ok, at, _offset} <- DateTime.from_iso8601(created) do
      at |> DateTime.add(15, :minute) |> DateTime.to_iso8601()
    else
      _ -> nil
    end
  end

  # what the room card draws (assets/js RoomCard): who, when, the
  # motion once published, the draw, the judge, and the room's short
  # link with its QR code
  defp room_card(state, room, session, club) do
    link = Cab.Sessions.short_url(session, room["no"])
    motion = room["Motion"]

    qr =
      case CabWeb.QR.matrix(link) do
        rows when is_list(rows) ->
          Enum.map(rows, &Enum.map_join(&1, fn d -> if d, do: "1", else: "0" end))

        _too_long ->
          []
      end

    Jason.encode!(%{
      club: club.name,
      session: state.event["name"],
      date: Calendar.strftime(session.scheduled_at || session.inserted_at, "%-d %b %Y"),
      starts: session.scheduled_at && Calendar.strftime(session.scheduled_at, "%H:%M"),
      room: room_label(room),
      motion: motion && motion["motion_text"],
      infoslide: motion && motion["infoslide"],
      prep_until: prep_until(room),
      teams:
        for room_team <- sorted_teams(room) do
          %{
            side: side_code(room_team["position"]),
            team: get_in(room_team, ["Team", "name"]) || "—",
            speakers: speaker_names(room_team)
          }
        end,
      judge: judge_name(room, state.signups),
      link: link,
      link_text: bare_url(link),
      qr: qr
    })
  end

  defp prep_until(room) do
    with iso when is_binary(iso) <- prep_deadline(room),
         {:ok, at, _} <- DateTime.from_iso8601(iso) do
      Calendar.strftime(at, "%H:%M")
    else
      _ -> nil
    end
  end

  defp my_room_label(%{rooms: rooms}, my_room_id) do
    case Enum.find(rooms, &(&1["id"] == my_room_id)) do
      nil -> ""
      room -> room_label(room)
    end
  end

  defp my_room_motion(%{rooms: rooms}, my_room_id) when is_integer(my_room_id) do
    case Enum.find(rooms, &(&1["id"] == my_room_id)) do
      %{"Motion" => %{"motion_text" => motion}} when is_binary(motion) -> motion
      _ -> nil
    end
  end

  defp my_room_motion(_state, _my_room_id), do: nil
end
