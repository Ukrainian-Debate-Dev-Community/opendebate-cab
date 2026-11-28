defmodule CabWeb.Tour.Demo do
  @moduledoc """
  The guided tours' world: a fictional club, its people and one
  session seen at each stage, shaped exactly like what the contexts and
  the engine hand cab's pages. Pure data - no engine call, no database
  write; the ids are negative so a read never meets a real row. The
  tours render cab's real page templates with it (`CabWeb.Tour.Pages`).
  """

  alias Cab.Accounts.User
  alias Cab.Clubs.{Club, Membership}
  alias Cab.Links.Link
  alias Cab.Sessions.Session

  @club_uuid "00000000-0000-4000-8000-00000000c1b0"
  @session_uuid "00000000-0000-4000-8000-000000005e55"

  # {participant id, name, node user id}; the first 16 speak, the last
  # two adjudicate (Petro chairs R1, Iryna R2)
  @people [
    {201, "Anna Shevchuk", -102},
    {202, "Bohdan Kravets", -104},
    {203, "Daryna Moroz", -105},
    {204, "Yurii Tkach", -106},
    {205, "Sofiia Lysenko", -107},
    {206, "Maksym Hnatiuk", -108},
    {207, "Olha Rudenko", -109},
    {208, "Taras Savchuk", -110},
    {209, "Kateryna Pavlenko", -111},
    {210, "Ivan Marchenko", -112},
    {211, "Viktoriia Zinchenko", -113},
    {212, "Roman Ostapenko", -114},
    {213, "Nadiia Kovalchuk", -115},
    {214, "Artem Polishchuk", -116},
    {215, "Liliia Bondarenko", -117},
    {216, "Denys Yatsenko", -118},
    {217, "Petro Bondar", -103},
    {218, "Iryna Melnyk", -119}
  ]

  @motions [
    {"This House would ban homework in primary schools", "education",
     "In several countries primary schools have dropped homework altogether."},
    {"This House regrets the rise of influencer culture", "media", nil}
  ]

  # ---------------------------------------------------------------
  # People
  # ---------------------------------------------------------------

  @doc "The club's head."
  def head,
    do: %User{id: -1, username: "daria-koval", name: "Daria Koval", node_user_id: -101}

  @doc "The speaker the participant tour follows."
  def speaker, do: user(201, -2)

  @doc "The adjudicator the adjudicator tour follows (R1's chair)."
  def chair, do: user(217, -3)

  @doc "Someone new to the club: the clubs part follows him joining."
  def newcomer,
    do: %User{id: -101, username: "mark-hrytsenko", name: "Mark Hrytsenko", node_user_id: -130}

  @doc "A guest: no account, a personal link."
  def guest,
    do: %User{id: -9, username: "guest-greta", name: "Greta Lys", node_user_id: nil, guest: true}

  defp user(participant_id, id) do
    {_pid, name, node} = List.keyfind(@people, participant_id, 0)
    username = name |> String.downcase() |> String.replace(" ", "-")
    %User{id: id, username: username, name: name, node_user_id: node}
  end

  defp people_users do
    for {{pid, name, node}, i} <- Enum.with_index(@people, 10) do
      %User{
        id: -i,
        username: name |> String.downcase() |> String.replace(" ", "-"),
        name: name,
        node_user_id: node
      }
      |> Map.put(:participant_id, pid)
    end
  end

  # ---------------------------------------------------------------
  # The club
  # ---------------------------------------------------------------

  @doc "The demo club."
  def club do
    %Club{
      id: -1,
      uuid: @club_uuid,
      name: "Riverside Debate Club",
      city: "Kyiv",
      meeting_info: "Thursdays at 18:30, room 204",
      description:
        "A weekly British Parliamentary practice night: newcomers and old hands debate side by side, and every round ends with feedback.",
      contacts: "@riverside_debate",
      formats: ["bp"],
      languages: ["en"],
      audiences: [],
      is_private: false,
      guest_form: member_form(),
      inserted_at: ~U[2026-09-01 10:00:00Z]
    }
  end

  # one question for members (their answer is saved) besides the
  # guests' built-in ones
  defp member_form do
    [
      %{
        "id" => "experience",
        "type" => "choice",
        "label" => "How long have you been debating?",
        "hint" => nil,
        "required" => true,
        "options" => ["New to it", "Up to a year", "More than a year"],
        "scope" => "both"
      }
    ]
  end

  @doc "The club's approved members, the head first."
  def members do
    head = %Membership{
      id: -1,
      club_id: -1,
      user_id: head().id,
      role: "head",
      status: "approved",
      user: head(),
      club: club(),
      inserted_at: ~U[2026-09-01 10:00:00Z]
    }

    rest =
      for user <- Enum.take(people_users(), 12) do
        %Membership{
          id: user.id,
          club_id: -1,
          user_id: user.id,
          role: "member",
          status: "approved",
          user: user,
          club: club(),
          inserted_at: ~U[2026-09-08 18:00:00Z]
        }
      end

    [head | rest]
  end

  @doc "People asking to join."
  def join_requests do
    for {{name, message}, i} <-
          Enum.with_index(
            [
              {"Mark Hrytsenko", "I debated at school and want to start again."},
              {"Zlata Fedorenko", "A friend brought me last week - I loved it."}
            ],
            0
          ) do
      user =
        if i == 0,
          do: newcomer(),
          else: %User{
            id: -100 - i,
            username: name |> String.downcase() |> String.replace(" ", "-"),
            name: name
          }

      %Membership{
        id: -100 - i,
        club_id: -1,
        user_id: user.id,
        role: "member",
        status: "pending",
        message: message,
        contact: "@" <> user.username,
        answers: [
          %{
            "id" => "experience",
            "label" => "How long have you been debating?",
            "type" => "choice",
            "value" => "Up to a year"
          }
        ],
        user: user,
        club: club(),
        inserted_at: DateTime.add(now(), -i, :day)
      }
    end
  end

  @doc "The followed speaker's membership."
  def membership(user) do
    %Membership{
      id: -50,
      club_id: -1,
      user_id: user.id,
      role: "member",
      status: "approved",
      answers: [
        %{
          "id" => "experience",
          "label" => "How long have you been debating?",
          "type" => "choice",
          "value" => "Up to a year"
        }
      ],
      club: club(),
      inserted_at: ~U[2026-09-08 18:00:00Z]
    }
  end

  # ---------------------------------------------------------------
  # The session, at each stage
  # ---------------------------------------------------------------

  @doc "Now, to the minute."
  def now, do: DateTime.utc_now() |> DateTime.truncate(:second) |> Map.put(:second, 0)

  # tonight's session starts at the next 18:30 UTC
  defp tonight do
    today = DateTime.to_date(now())
    at = DateTime.new!(today, ~T[18:30:00])
    if DateTime.compare(at, now()) == :gt, do: at, else: DateTime.add(at, 1, :day)
  end

  @doc "Tonight's session at `stage`: :signup, :closed, :running or :done."
  def session(stage) do
    base = %Session{
      id: -31,
      uuid: @session_uuid,
      club_id: -1,
      club: club(),
      format: "bp",
      name: "Thursday night",
      scheduled_at: tonight(),
      max_participants: 24,
      signups_count: length(@people),
      inserted_at: DateTime.add(now(), -5, :day)
    }

    case stage do
      :signup ->
        base

      :closed ->
        %{base | signups_closed_at: now(), draft_allocation: draft(1)}

      :running ->
        %{base | signups_closed_at: now(), started_at: now(), rooms_count: 2, room_ids: [71, 72]}

      :done ->
        %{
          base
          | signups_closed_at: now(),
            started_at: now(),
            finished_at: now(),
            rooms_count: 2,
            room_ids: [71, 72],
            winner_name: "Anna Shevchuk & Bohdan Kravets"
        }
    end
  end

  @doc "The club's earlier sessions (finished), newest first."
  def past_sessions do
    for {weeks, name} <- [{1, "Thursday night"}, {2, "Thursday night"}, {3, "Novices' night"}] do
      at = DateTime.add(tonight(), -7 * weeks, :day)

      %Session{
        id: -31 - weeks,
        uuid: "00000000-0000-4000-8000-00000000500#{weeks}",
        club_id: -1,
        club: club(),
        format: "bp",
        name: name,
        scheduled_at: at,
        started_at: at,
        signups_closed_at: at,
        finished_at: DateTime.add(at, 3, :hour),
        rooms_count: 2,
        signups_count: 17,
        winner_name: "Daryna Moroz & Yurii Tkach",
        inserted_at: DateTime.add(at, -6, :day)
      }
    end
  end

  # the allocator's draft: room 1 filled in, room 2 waiting
  defp draft(rooms) do
    for room <- 1..rooms, {key, pid} <- room_seats(room), into: %{}, do: {key, pid}
  end

  defp room_seats(1) do
    [
      {"1:og:1", 202},
      {"1:og:2", 203},
      {"1:oo:1", 201},
      {"1:oo:2", 204},
      {"1:cg:1", 205},
      {"1:cg:2", 206},
      {"1:co:1", 207},
      {"1:co:2", 208},
      {"1:judge", 217}
    ]
  end

  @doc "The engine's sign-ups (participants)."
  def signups(stage \\ :running) do
    # before the draw two speakers are not here yet; once rooms exist,
    # everyone seated was checked in
    late = if stage in [:signup, :closed], do: [214, 216], else: []

    for {pid, name, node} <- @people,
        do: %{
          "id" => pid,
          "display_name" => name,
          "user_id" => node,
          "checked_in" => pid not in late
        }
  end

  @doc """
  The session's state as `Cab.Sessions.state/1` gives it. `room` moves
  R1 along: :pending (no motion), :judging (motion out, prep running),
  :completed (the ballot in), :confirmed.
  """
  def state(stage, room \\ :judging) do
    rooms =
      case stage do
        stage when stage in [:signup, :closed] -> []
        :running -> [room(1, room), room(2, :judging)]
        :done -> [room(1, :confirmed), room(2, :confirmed)]
      end

    %{
      event: %{
        "id" => -11,
        "name" => "Thursday night",
        "status" => if(stage == :done, do: "completed", else: "scheduled")
      },
      round: if(rooms != [], do: %{"id" => -21, "sequence" => 1}),
      signups: signups(stage),
      rooms: rooms,
      stage: stage
    }
  end

  # R1: Bohdan & Daryna (OG), Anna & Yurii (OO), ... chaired by Petro;
  # R2: the next eight, chaired by Iryna
  defp room(no, status) do
    {speakers, chair} =
      if no == 1,
        do: {Enum.slice(@people, 0, 8), Enum.at(@people, 16)},
        else: {Enum.slice(@people, 8, 8), Enum.at(@people, 17)}

    # OG, OO, CG, CO; R1's order puts Anna (OO) second
    teams =
      if no == 1,
        do: [[1, 2], [0, 3], [4, 5], [6, 7]],
        else: [[0, 1], [2, 3], [4, 5], [6, 7]]

    ranks = if no == 1, do: [2, 1, 3, 4], else: [1, 3, 2, 4]
    scored? = status in [:completed, :confirmed]
    {text, keyword, infoslide} = Enum.at(@motions, no - 1)

    %{
      "id" => 70 + no,
      "no" => no,
      "status" => Atom.to_string(status),
      "Motion" =>
        if(status != :pending,
          do: %{"motion_text" => text, "keyword" => keyword, "infoslide" => infoslide}
        ),
      "prep_until" =>
        if(status == :judging, do: now() |> DateTime.add(9, :minute) |> DateTime.to_iso8601()),
      "RoomAdjudicators" => [
        %{"id" => 900 + no, "role" => "chair", "EventParticipant" => participant(chair)}
      ],
      "RoomTeams" =>
        for {{pair, rank}, position} <- teams |> Enum.zip(ranks) |> Enum.with_index(1) do
          %{
            "id" => 100 * no + position,
            "position" => position,
            "rank" => if(scored?, do: rank),
            "Team" => %{"id" => 1000 * no + position, "name" => "Team #{no}.#{position}"},
            "RoomSpeakers" =>
              for {index, seat} <- Enum.with_index(pair) do
                person = Enum.at(speakers, index)
                points = points(no, position, seat, rank)

                %{
                  "id" => 5000 + elem(person, 0),
                  "EventParticipant" => participant(person),
                  "Scores" => if(scored?, do: [%{"value" => "#{points}.00"}], else: [])
                }
              end
          }
        end
    }
  end

  # R1's points are Petro's ballot in the tour (OG 76+75, OO 77+76, CG
  # 74+73, CO 72+71); R2 follows its places
  defp points(1, position, seat, _rank),
    do: Enum.at([[76, 75], [77, 76], [74, 73], [72, 71]], position - 1) |> Enum.at(seat)

  defp points(_no, _position, seat, rank), do: 79 - rank * 2 - seat

  defp participant({pid, name, node}),
    do: %{"id" => pid, "display_name" => name, "user_id" => node}

  @doc "The feedback the teams sent (engine records as `Cab.Feedback` shows them)."
  def feedback(stage) do
    sent = if stage == :done, do: [1, 2, 3, 4], else: [2, 3]

    for position <- sent do
      {accuracy, reasoning, text} =
        Enum.at(
          [
            {8, 7, "A clear call; the comparison of OO and CG was convincing."},
            {8, 7, "A clear call, and useful advice on rebuttal."},
            {7, 7, "Good, though we would have liked more on our extension."},
            {6, 7, "We disagree with fourth, but the reasons were clear."}
          ],
          position - 1
        )

      %{
        id: position,
        room_id: 71,
        adjudicator_id: 217,
        adjudicator: "Petro Bondar",
        team_id: 1000 + position,
        team: "Team 1.#{position}",
        accuracy: accuracy,
        reasoning: reasoning,
        score: (accuracy + reasoning) / 2,
        discussion: text
      }
    end
  end

  @doc "A guest's personal link."
  def guest_link do
    %Link{
      id: -61,
      code: "demo-guest-link-0000000000000000000",
      engine_participant_id: 216,
      answers: [
        %{
          "id" => "email",
          "label" => "Your e-mail",
          "type" => "email",
          "value" => "greta@example.org"
        }
      ],
      user: guest(),
      club: club(),
      session: session(:signup),
      inserted_at: DateTime.add(now(), -2, :day)
    }
  end

  @doc "The speaker's figures as the engine reports them (demo numbers)."
  def stats do
    %{
      "overview" => %{
        "total_debates_ranked" => 14,
        "total_ballots_received" => 14,
        "average_speaker_score" => 75.4,
        "highest_score" => 80,
        "lowest_score" => 71
      },
      "placements" => %{"first_places" => 5, "win_rate_percentage" => 35.7}
    }
  end

  @doc "The speaker's history rows."
  def history(role) do
    for {session, i} <- Enum.with_index(past_sessions()) do
      %{
        date: session.finished_at,
        club: club().name,
        club_uuid: @club_uuid,
        session_uuid: session.uuid,
        role: role,
        won: role == "speaker" and i == 0
      }
    end
  end
end
