defmodule Cab.Format do
  @moduledoc """
  The debate formats cab runs, one per session: the room's sides in the
  engine's position order (position 1 is the first side), the seats a
  team has, the score range and the engine's format, found by its code.
  A room seats every speaker and one judge. The words for sides and
  roles are CabWeb.SessionFormat's.

  - British Parliamentary (`bp`): four teams of two - OG, OO, CG, CO.
  - Australs (`aus`): Government v Opposition, three speakers a team
    (the third is the analyst), no reply speech, scored like BP.
  """

  @enforce_keys [:key, :code, :sides, :seats, :score_min, :score_max]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          key: String.t(),
          code: String.t(),
          sides: [String.t()],
          seats: pos_integer(),
          score_min: integer(),
          score_max: integer()
        }

  @formats [
    %{
      key: "bp",
      code: "BP",
      sides: ~w(og oo cg co),
      seats: 2,
      score_min: 50,
      score_max: 100
    },
    %{
      key: "aus",
      code: "AUS",
      sides: ~w(gov opp),
      seats: 3,
      score_min: 50,
      score_max: 100
    }
  ]

  @default "bp"

  @doc "Every format, BP first."
  def all, do: Enum.map(@formats, &struct!(__MODULE__, &1))

  @doc "The formats' keys, as a session stores them."
  def keys, do: Enum.map(@formats, & &1.key)

  @doc "The format a session's key names (BP for anything unknown, as sessions began)."
  def get(key) when is_binary(key), do: Enum.find(all(), &(&1.key == key)) || default()
  def get(_key), do: default()

  @doc "The format of a session (or of anything carrying a `format` key)."
  def of(%{format: key}), do: get(key)
  def of(_session), do: default()

  def default, do: Enum.find(all(), &(&1.key == @default))

  @doc "Teams in a room."
  def teams(%__MODULE__{sides: sides}), do: length(sides)

  @doc "Speeches in a room: every team's seats."
  def speeches(%__MODULE__{} = format), do: teams(format) * format.seats

  @doc "People a room seats: its speakers and one judge."
  def room_seats(%__MODULE__{} = format), do: speeches(format) + 1

  @doc "The side at an engine position (1-based); nil past the last."
  def side(%__MODULE__{sides: sides}, position) when is_integer(position) and position > 0,
    do: Enum.at(sides, position - 1)

  def side(_format, _position), do: nil

  @doc "The engine position (1-based) of a side; nil for another format's side."
  def position(%__MODULE__{sides: sides}, side) do
    case Enum.find_index(sides, &(&1 == side)) do
      nil -> nil
      index -> index + 1
    end
  end

  @doc "Is a score a whole number within the format's range?"
  def valid_score?(%__MODULE__{score_min: min, score_max: max}, score),
    do: is_number(score) and score >= min and score <= max and trunc(score) == score
end
