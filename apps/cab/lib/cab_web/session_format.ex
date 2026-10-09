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

  def ordinal(1), do: "1st"
  def ordinal(2), do: "2nd"
  def ordinal(3), do: "3rd"
  def ordinal(rank), do: "#{rank}th"

  @doc "When the room's prep ends: 15 minutes after its motion was published, or nil."
  def prep_until(room) do
    with %{"created_at" => created} when is_binary(created) <- room["Motion"],
         {:ok, at, _offset} <- DateTime.from_iso8601(created) do
      DateTime.add(at, 15, :minute)
    else
      _ -> nil
    end
  end
end
