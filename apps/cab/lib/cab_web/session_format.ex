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
  def stage_words(:signup), do: "sign-ups open"
  def stage_words(:closed), do: "sign-ups closed"
  def stage_words(:running), do: "running"
  def stage_words(:done), do: "finished"

  @doc "A room's ballot state in words."
  def room_status_words("pending"), do: "waiting to start"
  def room_status_words("judging"), do: "debating — waiting for the ballot"
  def room_status_words("completed"), do: "ballot in"
  def room_status_words("confirmed"), do: "ballot in"
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

  def ordinal(1), do: "1st"
  def ordinal(2), do: "2nd"
  def ordinal(3), do: "3rd"
  def ordinal(rank), do: "#{rank}th"

  @doc "The session's date — the planned start when there is one."
  def session_date(%{scheduled_at: %DateTime{} = at}),
    do: Calendar.strftime(at, "%-d %b %Y, %H:%M")

  def session_date(session), do: Calendar.strftime(session.inserted_at, "%-d %b %Y")
end
