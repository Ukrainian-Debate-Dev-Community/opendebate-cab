defmodule Cab.Feedback do
  @moduledoc """
  Feedback on adjudicators at club nights. Everything lives in the
  engine: the event's form (two questions that make the score), each
  team's feedback with its answers, and the adjudicator statistics with
  a base vote. cab keeps nothing of it; it reads the event's feedback
  as the club head and shows each person only their part:

    * the team that sent a feedback sees it right away;
    * the adjudicator sees every feedback about them once the club head
      has finished the session, without the team;
    * the club head always sees everything, with the team, and who has
      not sent theirs yet;
    * everyone sees the average, where a base of 5 counts as one vote.

  One feedback per team on its room's adjudicator, after the ballot is
  in and until the session is finished. Discussion (the engine's
  comment) is required here, though optional in the engine.
  """

  use Gettext, backend: CabWeb.Gettext

  require Logger

  alias Cab.Accounts.User
  alias Cab.Clubs.Club
  alias Cab.{Accounts, Clubs, EngineApi, Links, Repo, Sessions}
  alias Cab.Sessions.Session

  @base 5
  @keys ~w(accuracy reasoning)
  @discussion_max 5000

  @doc "The most characters the discussion has."
  def discussion_max, do: @discussion_max

  @doc "The base that counts as one vote in an adjudicator's average."
  def base, do: @base

  # the club-night form; labels are the engine's record of the question
  defp questions do
    [
      %{
        key: "accuracy",
        label: "How accurate was the adjudicator's call?",
        type: "integer",
        min_value: 1,
        max_value: 10,
        required: true,
        counts_in_score: true,
        position: 1
      },
      %{
        key: "reasoning",
        label: "How was the adjudicator's reasoning?",
        type: "integer",
        min_value: 1,
        max_value: 10,
        required: true,
        counts_in_score: true,
        position: 2
      }
    ]
  end

  @doc "The question shown to people, in their language."
  def question_label("accuracy"), do: gettext("How accurate was the adjudicator's call?")
  def question_label("reasoning"), do: gettext("How was the adjudicator's reasoning?")

  # ---------------------------------------------------------------
  # The form
  # ---------------------------------------------------------------

  @doc """
  Makes sure the session's engine event carries the club-night form:
  the questions it lacks are added (opening a session, or lazily for a
  session from before feedback). `:ok` or `{:error, message}`.
  """
  def ensure_form(%Session{} = session) do
    with {:ok, actor} <- Clubs.club_actor(club_of(session)),
         {:ok, present} <- EngineApi.feedback_questions(actor, session.engine_event_id) do
      have = MapSet.new(present, & &1["key"])

      questions()
      |> Enum.reject(&MapSet.member?(have, &1.key))
      |> Enum.reduce_while(:ok, fn question, :ok ->
        case EngineApi.create_feedback_question(actor, session.engine_event_id, question) do
          {:ok, _} -> {:cont, :ok}
          error -> {:halt, error}
        end
      end)
    end
  end

  # ---------------------------------------------------------------
  # Sending
  # ---------------------------------------------------------------

  @doc """
  The team of `user` sends its feedback on the room's adjudicator.
  `attrs`: `%{"accuracy", "reasoning", "discussion"}`. Returns `:ok`,
  `{:error, %{field => message}}` for the form, `{:error, :conflict,
  message}` when the team already sent or feedback is not open, or
  `{:error, message}`.
  """
  def submit(%User{} = user, %Session{} = session, room_id, attrs) do
    session = %{session | club: club_of(session)}

    with {:ok, form} <- parse(attrs),
         {:ok, state} <- Sessions.state(session),
         {:ok, room} <- find_room(state, room_id),
         :ok <- require_open(session, room),
         {:ok, room_team} <- team_of(state, room, user),
         {:ok, chair_id} <- chair_of(room),
         :ok <- ensure_form(session),
         {:ok, actor} <- actor_for(user, session),
         {:ok, _} <-
           EngineApi.submit_feedback(actor, room["id"], %{
             adjudicator_id: chair_id,
             issuer_team_id: get_in(room_team, ["Team", "id"]),
             comment: form.discussion,
             answers: [
               %{key: "accuracy", value: form.accuracy},
               %{key: "reasoning", value: form.reasoning}
             ]
           }) do
      Sessions.broadcast(session)
      :ok
    else
      {:error, "Feedback has already been submitted" <> _} ->
        {:error, :conflict, gettext("Your team already sent feedback.")}

      other ->
        other
    end
  end

  defp parse(attrs) do
    errors =
      %{}
      |> check_score(attrs, "accuracy")
      |> check_score(attrs, "reasoning")
      |> check_discussion(attrs)

    if errors == %{} do
      {:ok, discussion} = discussion(attrs)

      {:ok,
       %{
         accuracy: score_value(attrs["accuracy"]),
         reasoning: score_value(attrs["reasoning"]),
         discussion: discussion
       }}
    else
      {:error, errors}
    end
  end

  defp check_score(errors, attrs, key) do
    case score_value(attrs[key]) do
      score when is_integer(score) and score in 1..10 -> errors
      _ -> Map.put(errors, key, gettext("Enter a whole number from 1 to 10."))
    end
  end

  defp check_discussion(errors, attrs) do
    case discussion(attrs) do
      {:ok, _text} -> errors
      {:error, message} -> Map.put(errors, "discussion", message)
    end
  end

  defp discussion(attrs) do
    Cab.Text.check(attrs["discussion"],
      required: true,
      max: @discussion_max,
      multiline: true,
      message: gettext("Explain your feedback.")
    )
  end

  defp score_value(value) when is_integer(value), do: value

  defp score_value(value) when is_binary(value) do
    case Integer.parse(String.trim(value)) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp score_value(_value), do: nil

  defp find_room(state, room_id) do
    case Enum.find(state.rooms, &(&1["id"] == room_id)) do
      nil -> {:error, gettext("That room is not part of this session.")}
      room -> {:ok, room}
    end
  end

  @doc "Is feedback open for this room: the ballot is in and the session not finished?"
  def open?(%Session{finished_at: finished}, room),
    do: is_nil(finished) and room["status"] in ["completed", "confirmed"]

  defp require_open(session, room) do
    cond do
      session.finished_at ->
        {:error, :conflict, gettext("The session is finished, so feedback is closed.")}

      room["status"] not in ["completed", "confirmed"] ->
        {:error, :conflict, gettext("Feedback opens once the room's ballot is in.")}

      true ->
        :ok
    end
  end

  defp team_of(state, room, user) do
    case my_room_team(state, room, user) do
      nil -> {:error, :forbidden}
      room_team -> {:ok, room_team}
    end
  end

  defp chair_of(room) do
    case chair_id(room) do
      nil -> {:error, gettext("This room has no adjudicator.")}
      id -> {:ok, id}
    end
  end

  # a member sends as themselves; a guest has no engine account, so
  # once cab has checked the seat the engine call runs as the club head
  defp actor_for(user, session) do
    if Links.guest?(user.id) do
      Clubs.club_actor(session.club)
    else
      case Accounts.ensure_node_user(user) do
        %User{node_user_id: id} when is_integer(id) -> {:ok, id}
        _ -> {:error, gettext("Something went wrong, try again.")}
      end
    end
  end

  # ---------------------------------------------------------------
  # Who is who in a room
  # ---------------------------------------------------------------

  @doc "The participant id of `user` in this session, or nil."
  def my_participant_id(%{signups: signups}, %User{} = user) do
    guest_ids = Links.participant_ids(user.id)
    node = user.node_user_id

    Enum.find_value(signups, fn participant ->
      own? =
        (is_integer(node) and participant["user_id"] == node) or
          participant["id"] in guest_ids

      own? && participant["id"]
    end)
  end

  def my_participant_id(_state, _user), do: nil

  @doc "The room team `user` speaks for in this room, or nil."
  def my_room_team(state, room, %User{} = user) do
    case my_participant_id(state, user) do
      nil -> nil
      id -> Enum.find(room["RoomTeams"] || [], &speaks_for?(&1, id))
    end
  end

  def my_room_team(_state, _room, _user), do: nil

  defp speaks_for?(room_team, participant_id) do
    Enum.any?(
      room_team["RoomSpeakers"] || [],
      &(get_in(&1, ["EventParticipant", "id"]) == participant_id)
    )
  end

  @doc "The participant id of the room's chair, or nil."
  def chair_id(room) do
    Enum.find_value(room["RoomAdjudicators"] || [], fn adj ->
      adj["role"] == "chair" && get_in(adj, ["EventParticipant", "id"])
    end)
  end

  defp team_id(room_team), do: get_in(room_team, ["Team", "id"])

  # ---------------------------------------------------------------
  # Reading - always as the club head, then filtered
  # ---------------------------------------------------------------

  @doc "Every feedback of the session (engine records), or [] when unreadable."
  def all(%Session{} = session) do
    with {:ok, actor} <- Clubs.club_actor(club_of(session)),
         {:ok, rows} when is_list(rows) <-
           EngineApi.event_feedback(actor, session.engine_event_id) do
      Enum.map(rows, &entry/1)
    else
      error ->
        Logger.warning("feedback unreadable for #{session.uuid}: #{inspect(error)}")
        []
    end
  end

  # one feedback as cab shows it
  defp entry(row) do
    answers = Map.new(row["answers"] || [], &{&1["key"], &1["value"]})

    %{
      id: row["id"],
      room_id: row["room_id"],
      adjudicator_id: row["adjudicator_id"],
      adjudicator: get_in(row, ["Adjudicator", "display_name"]),
      team_id: row["issuer_team_id"],
      team: get_in(row, ["IssuerTeam", "name"]),
      accuracy: answers["accuracy"],
      reasoning: answers["reasoning"],
      score: number(row["score"]),
      discussion: row["comment"]
    }
  end

  defp number(value) when is_number(value), do: value

  defp number(value) when is_binary(value) do
    case Float.parse(value) do
      {number, _} -> number
      :error -> nil
    end
  end

  defp number(_value), do: nil

  @doc "The feedback this room team sent, or nil."
  def sent_by(feedback, room, room_team) do
    Enum.find(feedback, &(&1.room_id == room["id"] and &1.team_id == team_id(room_team)))
  end

  @doc """
  The rooms where the user's team still owes feedback: ballot in,
  session not finished, nothing sent yet. Reads the engine only when
  such a room exists.
  """
  def awaiting(%Session{} = session, state, %User{} = user) do
    candidates =
      for room <- state.rooms,
          state.stage != :done,
          open?(session, room),
          room_team = my_room_team(state, room, user),
          room_team != nil,
          do: {room, room_team}

    case candidates do
      [] ->
        []

      _ ->
        feedback = all(session)
        for {room, room_team} <- candidates, sent_by(feedback, room, room_team) == nil, do: room
    end
  end

  def awaiting(_session, _state, _user), do: []

  @doc "The feedback the user's team sent in this room, or nil."
  def own_for_room(%Session{} = session, state, room, %User{} = user) do
    case my_room_team(state, room, user) do
      nil -> nil
      room_team -> sent_by(all(session), room, room_team)
    end
  end

  @doc """
  The feedback on `user` as an adjudicator in this session: nothing
  until the session is finished, then every entry without its team, in
  an order that does not follow the teams.
  """
  def on_adjudicator(%Session{finished_at: nil}, _state, _user), do: []

  def on_adjudicator(%Session{} = session, state, %User{} = user) do
    case my_participant_id(state, user) do
      nil ->
        []

      id ->
        if Enum.any?(state.rooms, &(chair_id(&1) == id)) do
          session
          |> all()
          |> Enum.filter(&(&1.adjudicator_id == id))
          |> Enum.map(&Map.drop(&1, [:team, :team_id, :id]))
          |> Enum.sort_by(&:erlang.phash2({session.uuid, &1.discussion, &1.score}))
        else
          []
        end
    end
  end

  @doc """
  The average with the base vote for the adjudicator `user` was in
  this session, from the engine's statistics; nil when not theirs.
  """
  def my_average(%Session{} = session, state, %User{} = user) do
    with id when is_integer(id) <- my_participant_id(state, user),
         {:ok, actor} <- Clubs.club_actor(club_of(session)),
         {:ok, rows} when is_list(rows) <-
           EngineApi.adjudicator_stats(actor, session.engine_event_id, @base),
         %{"avg_feedback" => avg} <- Enum.find(rows, &(&1["id"] == id)) do
      number(avg)
    else
      _ -> nil
    end
  end

  @doc """
  For the club head: per room, how many of its teams sent feedback and
  how many teams there are (`%{room_id => {sent, teams}}`).
  """
  def progress(state, feedback) do
    Map.new(state.rooms, fn room ->
      teams = Enum.count(room["RoomTeams"] || [], &team_id/1)
      sent = Enum.count(feedback, &(&1.room_id == room["id"]))
      {room["id"], {sent, teams}}
    end)
  end

  # ---------------------------------------------------------------
  # My page
  # ---------------------------------------------------------------

  @doc """
  The rooms where the user's team still owes feedback, across their
  running sessions: `[%{session, room}]`.
  """
  def to_give(%User{} = user) do
    for %{session: session, club: club} <- Sessions.user_schedule(user),
        session.started_at != nil and session.finished_at == nil,
        session = %{session | club: club},
        {:ok, state} <- [Sessions.state(session)],
        room <- awaiting(session, state, user),
        do: %{session: session, room: room}
  end

  @doc """
  The feedback on the user as an adjudicator in their latest finished
  sessions (`limit` of them), anonymous: `[%{session, state, entries,
  average}]`, only sessions with feedback.
  """
  def on_me_recent(%User{} = user, limit \\ 5) do
    user
    |> Sessions.user_history()
    |> Enum.filter(&(&1.role == "adjudicator"))
    |> Enum.take(limit)
    |> Enum.flat_map(fn row ->
      with %Session{} = session <- Repo.get_by(Session, uuid: row.session_uuid),
           session = Repo.preload(session, :club),
           {:ok, state} <- Sessions.state(session),
           [_ | _] = entries <- on_adjudicator(session, state, user) do
        [
          %{
            session: session,
            state: state,
            entries: entries,
            average: my_average(session, state, user)
          }
        ]
      else
        _ -> []
      end
    end)
  end

  @doc "The feedback keys, in form order."
  def keys, do: @keys

  defp club_of(%Session{club: %Club{} = club}), do: club
  defp club_of(%Session{club_id: id}), do: Repo.get!(Club, id)
end
