defmodule CabWeb.BallotForm do
  @moduledoc """
  Bridges the engine's room shape and `CabWeb.Ui.ballot/1` for the
  HTML ballot pages of both role trees: builds the component's
  `teams` assigns from a room (optionally echoing a submitted
  `ballot` params map back, marking tied totals amber), and parses
  those params into the `Cab.Sessions.submit_ballot/4` scores list.
  Sides and seats are the session format's (Cab.Format); each side's
  speaking roles are below.
  """

  use Gettext, backend: CabWeb.Gettext

  alias Cab.Format

  # each side's speakers in speaking order: BP's two, Australs' three
  # (the third the whip)
  @roles %{
    "og" => ["PM", "DPM"],
    "oo" => ["LO", "DLO"],
    "cg" => ["MG", "GW"],
    "co" => ["MO", "OW"],
    "gov" => ["PM", "DPM", "GW"],
    "opp" => ["LO", "DLO", "OW"]
  }

  @doc """
  The `teams` assign for `CabWeb.Ui.ballot/1`: one entry per room
  team in table (og/oo/cg/co) order, each position row a dropdown of
  the team's speakers. With `ballot_params` (the submitted `ballot`
  map on a failed POST) the chosen speakers, iron flags and scores
  are echoed back and teams with tied totals carry `tied: true`.
  Without params, a room that already carries submitted scores
  prefills them - editing a ballot never means retyping it.
  """
  def teams(room, %Format{} = format, ballot_params \\ nil) do
    tied = tied_sides(ballot_params, format)

    room["RoomTeams"]
    |> List.wrap()
    |> Enum.sort_by(& &1["position"])
    |> Enum.map(fn room_team ->
      side = Format.side(format, room_team["position"])

      slots =
        Enum.map(CabWeb.SessionFormat.room_speakers(room_team), fn speaker ->
          participant = speaker["EventParticipant"] || %{}
          {participant["display_name"] || "?", participant["id"], slot_score(speaker)}
        end)

      # a team short of speakers carries one participant on more than
      # one engine slot: those rows prefill that speaker, iron
      # pre-checked on every repeat; the dropdown lists them once
      options = Enum.uniq(Enum.map(slots, fn {label, id, _score} -> {label, id} end))

      rows =
        roles(side)
        |> Enum.with_index()
        |> Enum.map(fn {role, index} ->
          submitted = params_for(ballot_params, side, role)
          {_label, default, stored} = Enum.at(slots, index, {nil, nil, nil})

          repeat? =
            default != nil and Enum.any?(Enum.take(slots, index), &(elem(&1, 1) == default))

          %{
            role: role,
            role_label: role_label(role),
            speakers: options,
            selected: submitted["speaker"] || default,
            iron: iron?(submitted["iron"]) or (is_nil(ballot_params) and repeat?),
            score: submitted["score"] || (is_nil(ballot_params) && stored) || nil
          }
        end)

      %{
        side: side,
        # the people at this side; team names stay internal
        name: CabWeb.SessionFormat.speaker_names(room_team),
        rows: rows,
        tied: side in tied
      }
    end)
  end

  @doc "A speaking position as people read it (the role key stays the data)."
  def role_label("PM"), do: gettext("PM")
  def role_label("DPM"), do: gettext("DPM")
  def role_label("LO"), do: gettext("LO")
  def role_label("DLO"), do: gettext("DLO")
  def role_label("MG"), do: gettext("MG")
  def role_label("GW"), do: gettext("GW")
  def role_label("MO"), do: gettext("MO")
  def role_label("OW"), do: gettext("OW")
  def role_label(role), do: role

  @doc """
  The submitted `ballot` params -
  `%{"og" => %{"PM" => %{"speaker" => _, "iron" => _, "score" => _}, ...}, ...}`
  - as the flat scores list `Cab.Sessions.submit_ballot/4` takes.
  """
  def scores_from_params(%{} = ballot_params, %Format{} = format) do
    for {side, position} <- Enum.with_index(format.sides, 1),
        role <- roles(side),
        row = params_for(ballot_params, side, role),
        row != %{} do
      %{
        "position" => position,
        "speaker_participant_id" => parse_int(row["speaker"]),
        "iron" => iron?(row["iron"]),
        "score" => parse_score(row["score"])
      }
    end
  end

  def scores_from_params(_ballot_params, _format), do: []

  @doc "A side's speaking roles (Cab.Format side)."
  def roles(side), do: Map.fetch!(@roles, side)

  # the slot's already-submitted score, riding along the room read
  defp slot_score(%{"Scores" => [%{"value" => value} | _]}), do: value
  defp slot_score(_speaker), do: nil

  defp params_for(nil, _side, _role), do: %{}

  defp params_for(ballot_params, side, role) do
    case get_in(ballot_params, [to_string(side), role]) do
      %{} = row -> row
      _ -> %{}
    end
  end

  # checkboxes POST "on" when ticked and are absent otherwise
  defp iron?(value), do: value not in [nil, false, "false"]

  defp parse_int(value) when is_integer(value), do: value

  defp parse_int(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_int(_value), do: nil

  defp parse_score(value) when is_number(value), do: value / 1

  defp parse_score(value) when is_binary(value) do
    case Float.parse(value) do
      {score, ""} -> score
      _ -> nil
    end
  end

  defp parse_score(_value), do: nil

  # sides whose submitted totals collide - the amber tied state
  defp tied_sides(nil, _format), do: []

  defp tied_sides(ballot_params, format) do
    totals =
      Enum.map(format.sides, fn side ->
        total =
          roles(side)
          |> Enum.map(&parse_score(params_for(ballot_params, side, &1)["score"]))
          |> Enum.reject(&is_nil/1)
          |> Enum.sum()

        {side, total}
      end)

    duplicated =
      totals
      |> Enum.frequencies_by(fn {_side, total} -> total end)
      |> Enum.filter(fn {_total, count} -> count > 1 end)
      |> Enum.map(fn {total, _count} -> total end)

    for {side, total} <- totals, total in duplicated, do: side
  end
end
