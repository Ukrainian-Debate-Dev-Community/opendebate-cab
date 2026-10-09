defmodule CabWeb.SessionFormat do
  @moduledoc """
  The ONE place sessions, rooms and teams turn into words on a page —
  imported into every template, so a status reads the same everywhere.
  No pills: every status is written out.
  """

  @sides [{"OG", 1, "s-og"}, {"OO", 2, "s-oo"}, {"CG", 3, "s-cg"}, {"CO", 4, "s-co"}]

  @doc "The four BP sides as `{label, position, css_class}`."
  def sides, do: @sides

  @doc "A session's stage in words."
  def stage_words(:signup), do: "registration open"
  def stage_words(:closed), do: "registration closed"
  def stage_words(:running), do: "running"
  def stage_words(:done), do: "finished"

  @doc "A room's name inside its session: R1, R2, … (the engine id only as a fallback)."
  def room_label(%{"no" => no}) when is_integer(no), do: "R#{no}"
  def room_label(%{"id" => id}), do: "R#{id}"

  @doc "A URL as people read it: no scheme."
  def bare_url(url), do: String.replace(url, ~r{^https?://}, "")

  @doc "A room's ballot state in words."
  def room_status_words("pending"), do: "waiting to start"
  def room_status_words("judging"), do: "debating — waiting for the ballot"
  def room_status_words("completed"), do: "ballot submitted"
  def room_status_words("confirmed"), do: "ballot confirmed"
  def room_status_words("void"), do: "void"
  def room_status_words(other), do: other

  @doc "A room row's status: motion state + ballot state."
  def room_words(room) do
    motion = if room["Motion"], do: "motion set", else: "motion pending"
    "#{motion}, #{room_status_words(room["status"])}"
  end

  @doc "The team at a side position; a 1-speaker team is marked (iron)."
  def team_label(room, position) do
    case Enum.find(room["RoomTeams"] || [], &(&1["position"] == position)) do
      nil ->
        "—"

      room_team ->
        name = get_in(room_team, ["Team", "name"]) || "—"
        if iron_team?(room_team), do: "#{name} (iron)", else: name
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

  @doc "A room's teams in table (og/oo/cg/co) order."
  def sorted_teams(room), do: Enum.sort_by(room["RoomTeams"] || [], & &1["position"])

  def side_code(position), do: Enum.at(~w(OG OO CG CO), (position || 1) - 1)

  @doc "A team's speakers; an iron's two slots show once."
  def speaker_names(room_team) do
    (room_team["RoomSpeakers"] || [])
    |> Enum.map(&get_in(&1, ["EventParticipant", "display_name"]))
    |> Enum.reject(&is_nil/1)
    |> Enum.uniq()
    |> Enum.join(" & ")
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

  def ordinal(1), do: "1st"
  def ordinal(2), do: "2nd"
  def ordinal(3), do: "3rd"
  def ordinal(rank), do: "#{rank}th"
end
