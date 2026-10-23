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

  # the prep clock: 15 minutes from the motion's publication - the
  # engine ships created_at (ISO) with the motion; absent = no clock
  defp prep_deadline(room), do: room["prep_until"]

  # what the room card draws (assets/js ShareCard): who, when, the
  # motion once published, the draw, the judge, and the room's short
  # link with its QR code
  @doc """
  A shareable card: the picture (drawn in the browser from `card`, a
  JSON with its `kind`) and the same as text, side by side; clicking
  either copies it (the ShareCard hook).
  """
  attr :id, :string, required: true
  attr :card, :string, required: true

  def share_card(assigns) do
    ~H"""
    <div class="pad sharecard" id={@id} phx-hook="ShareCard" data-card={@card}>
      <p class="sharehint">
        {gettext("Click the picture or the text to copy it, then paste it into the chat.")}
        <span class="sharemsg" aria-live="polite"></span>
      </p>
      <div class="sharecols">
        <canvas
          id={"#{@id}-canvas"}
          data-card-image
          role="button"
          tabindex="0"
          aria-label={gettext("As a picture: copy it")}
          title={gettext("Copy the picture")}
        ></canvas>
        <pre
          id={"#{@id}-text"}
          class="sharetext"
          data-card-text
          role="button"
          tabindex="0"
          aria-label={gettext("As text: copy it")}
          title={gettext("Copy the text")}
        ></pre>
      </div>
    </div>
    """
  end

  # a room's sides in place order once the ballot is in, else by side
  defp result_rows(room) do
    teams = sorted_teams(room)
    if ballot_in?(room), do: Enum.sort_by(teams, &(&1["rank"] || 9)), else: teams
  end

  # the finished session's results card: every room's motion and its
  # sides in place order with the speakers' points (engine values)
  defp results_card(state, session, club) do
    link = Cab.Sessions.short_url(session)

    Jason.encode!(%{
      kind: "results",
      club: club.name,
      session: state.event["name"],
      date: DateTime.to_iso8601(session.scheduled_at || session.inserted_at),
      starts: session.scheduled_at && DateTime.to_iso8601(session.scheduled_at),
      link: link,
      link_text: bare_url(link),
      qr: qr_rows(link),
      rooms:
        for room <- state.rooms do
          motion = room["Motion"] || %{}

          %{
            room: room_label(room),
            keyword: motion["keyword"],
            motion: motion["motion_text"],
            infoslide: motion["infoslide"],
            rows:
              for room_team <- result_rows(room) do
                %{
                  side: side_code(room_team["position"]),
                  place: ballot_in?(room) && room_team["rank"] && ordinal(room_team["rank"]),
                  winner: room_team["rank"] == 1,
                  points: team_points(room_team),
                  team_points: rank_points(room, room_team),
                  speakers: Enum.map(speeches(room_team), &Map.take(&1, [:name, :points, :iron]))
                }
              end
          }
        end
    })
  end

  defp qr_rows(link) do
    case CabWeb.QR.matrix(link) do
      rows when is_list(rows) ->
        Enum.map(rows, &Enum.map_join(&1, fn d -> if d, do: "1", else: "0" end))

      _too_long ->
        []
    end
  end

  defp room_card(state, room, session, club) do
    link = Cab.Sessions.short_url(session, room["no"])
    motion = room["Motion"]

    qr = qr_rows(link)

    Jason.encode!(%{
      kind: "room",
      club: club.name,
      session: state.event["name"],
      date: DateTime.to_iso8601(session.scheduled_at || session.inserted_at),
      # exact instants; the browser shows them in the viewer's timezone
      starts: session.scheduled_at && DateTime.to_iso8601(session.scheduled_at),
      room: room_label(room),
      motion: motion && motion["motion_text"],
      infoslide: motion && motion["infoslide"],
      prep_until: prep_deadline(room),
      # the people who play, by side; team names stay internal
      sides:
        for room_team <- sorted_teams(room) do
          %{side: side_code(room_team["position"]), people: speaker_list(room_team)}
        end,
      judges: judges(room, state.signups),
      link: link,
      link_text: bare_url(link),
      qr: qr
    })
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
