defmodule CabWeb.SessionFormat do
  @moduledoc """
  The ONE place sessions, rooms and teams turn into words on a page -
  imported into every template, so a status reads the same everywhere.
  No pills: every status is written out.
  """

  use Gettext, backend: CabWeb.Gettext

  @doc "A format's sides (Cab.Format; BP by default) as `{label, position, css_class}`."
  def sides(format \\ Cab.Format.default()) do
    for {side, position} <- Enum.with_index(format.sides, 1),
        do: {side_short(side), position, "s-#{side}"}
  end

  @doc "A format's name (Cab.Format key); an unknown key as it is."
  def format_name("bp"), do: gettext("BP")
  def format_name("aus"), do: gettext("Australs")
  def format_name(key), do: key

  @doc "A side's short name (Cab.Format side): OG, OO, CG, CO in BP; Gov, Opp in Australs."
  def side_short("og"), do: gettext("OG")
  def side_short("oo"), do: gettext("OO")
  def side_short("cg"), do: gettext("CG")
  def side_short("co"), do: gettext("CO")
  def side_short("gov"), do: gettext("Gov")
  def side_short("opp"), do: gettext("Opp")

  @doc "A session's stage in words."
  def stage_words(:signup), do: gettext("registration open")
  def stage_words(:closed), do: gettext("registration closed")
  def stage_words(:running), do: gettext("running")
  def stage_words(:done), do: gettext("finished")

  @doc "The tag kind for a session's stage: open sign-ups, closed, running, done."
  def stage_kind(:signup), do: :info
  def stage_kind(:closed), do: :warn
  def stage_kind(:running), do: :ok
  def stage_kind(_stage), do: nil

  @doc "A room's name inside its session: R1, R2, ... (the engine id only as a fallback)."
  def room_label(%{"no" => no}) when is_integer(no), do: gettext("R%{number}", number: no)
  def room_label(%{"id" => id}), do: gettext("R%{number}", number: id)

  @doc "A URL as people read it: no scheme."
  def bare_url(url), do: String.replace(url, ~r{^https?://}, "")

  @doc "A room's ballot state in words."
  def room_status_words("pending"), do: gettext("waiting to start")
  def room_status_words("judging"), do: gettext("debating — waiting for the ballot")
  def room_status_words("completed"), do: gettext("ballot submitted")
  def room_status_words("confirmed"), do: gettext("ballot confirmed")
  def room_status_words("void"), do: gettext("void")
  def room_status_words(other), do: other

  @doc "A room row's status: motion state + ballot state."
  def room_words(room) do
    status = room_status_words(room["status"])

    if room["Motion"],
      do: gettext("motion set, %{status}", status: status),
      else: gettext("motion pending, %{status}", status: status)
  end

  @doc """
  The people speaking at a side position (team names stay internal);
  one person speaking twice is marked (iron).
  """
  def team_label(room, position) do
    case Enum.find(room["RoomTeams"] || [], &(&1["position"] == position)) do
      nil ->
        "—"

      room_team ->
        names = if (n = speaker_names(room_team)) == "", do: "—", else: n
        if iron_team?(room_team), do: gettext("%{team} (iron)", team: names), else: names
    end
  end

  defp iron_team?(room_team) do
    (room_team["RoomSpeakers"] || [])
    |> Enum.map(&get_in(&1, ["EventParticipant", "id"]))
    |> Enum.uniq()
    |> length() == 1
  end

  @doc "The chair's display name, resolved through the signups list."
  def judge_name(room, signups) do
    chair = Enum.find(room["RoomAdjudicators"] || [], &(&1["role"] == "chair"))

    with %{} <- chair,
         participant_id when not is_nil(participant_id) <-
           get_in(chair, ["EventParticipant", "id"]) do
      get_in(chair, ["EventParticipant", "display_name"]) ||
        Enum.find_value(signups, &(&1["id"] == participant_id && &1["display_name"])) || "—"
    else
      _ -> "—"
    end
  end

  @doc """
  The room's adjudicators, the chair first: `%{name, chair}` each,
  names resolved through the signups list like `judge_name/2`.
  """
  def judges(room, signups) do
    (room["RoomAdjudicators"] || [])
    |> Enum.sort_by(&(&1["role"] != "chair"))
    |> Enum.map(fn adjudicator ->
      id = get_in(adjudicator, ["EventParticipant", "id"])

      name =
        get_in(adjudicator, ["EventParticipant", "display_name"]) ||
          Enum.find_value(signups, &(&1["id"] == id && &1["display_name"])) || "—"

      %{name: name, chair: adjudicator["role"] == "chair"}
    end)
  end

  @doc "The people speaking for a room team, each once (an iron speaker too)."
  def speaker_list(room_team) do
    (room_team["RoomSpeakers"] || [])
    |> Enum.map(&get_in(&1, ["EventParticipant", "display_name"]))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
  end

  @doc """
  A room team's speaker slots in speaking order: the order the engine
  made them (their ids) - its reads list them in no set order.
  """
  def room_speakers(room_team), do: Enum.sort_by(room_team["RoomSpeakers"] || [], & &1["id"])

  @doc "A room's teams in table (position) order."
  def sorted_teams(room), do: Enum.sort_by(room["RoomTeams"] || [], & &1["position"])

  @doc "The short name of the side at an engine position, in a format (BP by default)."
  def side_code(position, format \\ Cab.Format.default()) do
    side = Cab.Format.side(format, position || 1) || List.last(format.sides)
    side_short(side)
  end

  @doc "A team's speakers; an iron's two slots show once."
  def speaker_names(room_team) do
    (room_team["RoomSpeakers"] || [])
    |> Enum.map(&get_in(&1, ["EventParticipant", "display_name"]))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.join(" & ")
  end

  @doc "The label of the room a feedback entry is about, R1 or -."
  def feedback_room_label(%{rooms: rooms}, %{room_id: room_id}) do
    case Enum.find(rooms, &(&1["id"] == room_id)) do
      nil -> "—"
      room -> room_label(room)
    end
  end

  @doc "Is the room's ballot in (submitted or confirmed)?"
  def ballot_in?(room), do: room["status"] in ["completed", "confirmed"]

  @doc """
  A team's speeches in speaking order: `%{name, points, iron}`. An
  iron speaks twice; the engine flags the speech that stays out of the
  speaker tab, and without a flag the later of the two is that one.
  """
  def speeches(room_team) do
    (room_team["RoomSpeakers"] || [])
    |> Enum.sort_by(&{&1["rank"] || 0, &1["id"] || 0})
    |> Enum.map_reduce(MapSet.new(), fn rs, seen ->
      pid = get_in(rs, ["EventParticipant", "id"])
      flagged = Map.get(rs, "is_iron")
      iron = if is_boolean(flagged), do: flagged, else: MapSet.member?(seen, pid)

      {%{
         name: get_in(rs, ["EventParticipant", "display_name"]),
         points: rs |> Map.get("Scores", []) |> List.first() |> score_value(),
         iron: iron
       }, MapSet.put(seen, pid)}
    end)
    |> elem(0)
  end

  @doc "The team's points in the room: the sum of its speeches, or nil before the ballot."
  def team_points(room_team) do
    points = for %{points: p} <- speeches(room_team), is_number(p), do: p
    if points == [], do: nil, else: Enum.sum(points)
  end

  @doc """
  The team points a side earns in a room by the engine's own standings
  rule (N - rank, N the teams in the room: 3/2/1/0 in BP), or nil
  before the ballot.
  """
  def rank_points(room, room_team) do
    case room_team["rank"] do
      rank when is_integer(rank) -> length(room["RoomTeams"] || []) - rank
      _ -> nil
    end
  end

  @doc "Points as people write them: 76, 75.5."
  def points_words(nil), do: "—"
  def points_words(points) when points == trunc(points), do: Integer.to_string(trunc(points))
  def points_words(points), do: :erlang.float_to_binary(points / 1, decimals: 1)

  defp score_value(%{"value" => value}) when is_number(value), do: value

  defp score_value(%{"value" => value}) when is_binary(value) do
    case Float.parse(value) do
      {number, _} -> number
      :error -> nil
    end
  end

  defp score_value(_score), do: nil

  def ordinal(1), do: gettext("1st")
  def ordinal(2), do: gettext("2nd")
  def ordinal(3), do: gettext("3rd")
  def ordinal(rank), do: gettext("%{rank}th", rank: rank)
end
