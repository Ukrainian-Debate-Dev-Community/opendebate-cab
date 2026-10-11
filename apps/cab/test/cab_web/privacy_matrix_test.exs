defmodule CabWeb.PrivacyMatrixTest do
  @moduledoc """
  The privacy matrix: every page and API read against every kind of
  viewer, for a public and a private club. Each cell is the expected
  outcome - 200, :signin (sent to /signin), :head_view (a head sent
  to the session's Rooms page), 401, 403 or 404. A private
  club differs from a public one only where a row says so.

  Set PRIVACY_MATRIX_OUT=path to also write the observed outcomes as
  JSON (the review page is built from it).
  """
  use CabWeb.ConnCase, async: false

  import Cab.Fixtures

  alias Cab.Clubs

  @viewers [:anonymous, :outsider, :guest_played, :guest_other, :member, :head, :admin]

  # {label, path, public outcomes, private outcomes (nil = same)}
  # outcome lists follow @viewers order
  @matrix [
    {"Front page", "/", List.duplicate(200, 7), nil},
    {"Global standings", "/standings/teams", List.duplicate(200, 7), nil},
    {"Club page", "/c/:club", List.duplicate(200, 7), nil},
    {"Club standings (latest finished session)", "/c/:club/standings/teams",
     List.duplicate(200, 7), [:signin, 403, 200, 403, 200, 200, 200]},
    {"Club roster", "/c/:club/members", List.duplicate(200, 7),
     [:signin, 403, 403, 403, 200, 200, 200]},
    {"Join request form", "/c/:club/join", [:signin, 200, :signin, :signin, 200, 200, 200], nil},
    {"Session page (live)", "/c/:club/s/:live",
     List.duplicate(200, 5) ++ [:head_view, :head_view], nil},
    {"Room page (live)", "/c/:club/s/:live/rooms/72", List.duplicate(200, 7), nil},
    {"Ballot page (member chairs the room)", "/c/:club/s/:live/rooms/72/ballot",
     [:signin, 403, 403, 403, 200, 200, 200], nil},
    {"Registration page", "/r/:live", List.duplicate(200, 7), nil},
    {"My page", "/me", [:signin, 200, :signin, :signin, 200, 200, 200], nil},
    {"Account", "/account", [:signin, 200, :signin, :signin, 200, 200, 200], nil},
    {"Owner: club edit", "/c/:club/owner", [:signin, 403, 403, 403, 403, 200, 200], nil},
    {"Owner: members and requests", "/c/:club/owner/members",
     [:signin, 403, 403, 403, 403, 200, 200], nil},
    {"Owner: live session", "/c/:club/owner/s/:live", [:signin, 403, 403, 403, 403, 200, 200],
     nil},
    {"Admin", "/admin", [404, 404, 404, 404, 404, 404, 200], nil},
    {"API: club profile", "/api/v1/clubs/:club", List.duplicate(200, 7), nil},
    {"API: club roster", "/api/v1/clubs/:club/members", List.duplicate(200, 7),
     [401, 403, 403, 403, 200, 200, 200]},
    {"API: session state", "/api/v1/sessions/:live", List.duplicate(200, 7), nil},
    {"API: guest links", "/api/v1/sessions/:live/links", [401, 403, 403, 403, 403, 200, 200], nil}
  ]

  defp ok(conn, data), do: Req.Test.json(conn, %{"status" => "success", "data" => data})

  defp room(id, status, chair_user_id) do
    %{
      "id" => id,
      "status" => status,
      "Motion" => %{"motion_text" => "THW test privacy"},
      "RoomAdjudicators" => [
        %{"role" => "chair", "EventParticipant" => %{"id" => 50, "user_id" => chair_user_id}}
      ],
      "RoomTeams" =>
        for position <- 1..4 do
          %{
            "id" => 100 + position,
            "position" => position,
            "rank" => position,
            "Team" => %{"name" => "Team #{position}"},
            "RoomSpeakers" => [
              %{"id" => 200 + position, "EventParticipant" => %{"id" => 300 + position}}
            ]
          }
        end
    }
  end

  defp stub_engine do
    Req.Test.set_req_test_to_shared()

    Req.Test.stub(Core.Engine, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/11"} ->
          ok(conn, %{"id" => 11, "name" => "Quiet night", "status" => "completed"})

        {"GET", "/api/events/12"} ->
          ok(conn, %{"id" => 12, "name" => "Live night", "status" => "ongoing"})

        {"GET", "/api/events/11/rounds"} ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        {"GET", "/api/events/12/rounds"} ->
          ok(conn, [%{"id" => 22, "sequence" => 1}])

        {"GET", "/api/events/11/participants"} ->
          ok(conn, [%{"id" => 41, "user_id" => nil, "role" => "speaker", "display_name" => "G"}])

        {"GET", "/api/events/12/participants"} ->
          ok(conn, [%{"id" => 42, "user_id" => nil, "role" => "speaker", "display_name" => "O"}])

        {"GET", "/api/rounds/21/rooms"} ->
          ok(conn, [room(71, "confirmed", 44)])

        {"GET", "/api/rounds/22/rooms"} ->
          ok(conn, [room(72, "judging", 44)])

        {"GET", "/api/events/11/standings/calculated/" <> _tab} ->
          ok(conn, [%{"id" => 1, "name" => "Team 1", "total_points" => 3}])

        {"GET", "/api/events/11/stats/adjudicators"} ->
          ok(conn, [])

        {"GET", "/api/users/history"} ->
          ok(conn, %{"as_adjudicator" => [], "as_player" => []})

        {"GET", "/api/users/schedule"} ->
          ok(conn, %{"as_adjudicator" => [], "as_player" => []})

        {"GET", "/api/users/" <> _stats} ->
          ok(conn, nil)
      end
    end)
  end

  defp world(private?) do
    stub_engine()
    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})

    club =
      if private?,
        do: elem(Clubs.update_club(club, %{"is_private" => "true"}), 1),
        else: club

    now = DateTime.utc_now(:second)

    finished =
      session_fixture(club,
        engine_event_id: 11,
        engine_round_id: 21,
        name: "Quiet night",
        started_at: now,
        rooms_count: 1,
        finished_at: now
      )

    live =
      session_fixture(club,
        engine_event_id: 12,
        engine_round_id: 22,
        name: "Live night",
        started_at: now,
        rooms_count: 1,
        signups_closed_at: now
      )

    member = user_fixture(%{node_user_id: 44})
    membership_fixture(member, club)
    # guests have no engine account: their link names their place
    guest_played = user_fixture(%{node_user_id: nil, username: "guest-played"})
    link_fixture(guest_played, finished, participant_id: 41)
    guest_other = user_fixture(%{node_user_id: nil, username: "guest-other"})
    link_fixture(guest_other, live, participant_id: 42)

    %{
      club: club,
      live: live,
      users: %{
        anonymous: nil,
        outsider: user_fixture(%{node_user_id: 55}),
        guest_played: guest_played,
        guest_other: guest_other,
        member: member,
        head: head,
        admin:
          user_fixture(%{node_user_id: 66})
          |> Ecto.Changeset.change(is_admin: true)
          |> Cab.Repo.update!()
      }
    }
  end

  defp path_for(template, world) do
    template
    |> String.replace(":club", world.club.uuid)
    |> String.replace(":live", world.live.uuid)
  end

  defp outcome(conn, user, path) do
    conn =
      if user,
        do: init_test_session(conn, %{user_id: user.id}),
        else: init_test_session(conn, %{})

    try do
      result = get(conn, path)

      case {result.status, Plug.Conn.get_resp_header(result, "location")} do
        {302, ["/signin"]} -> :signin
        {302, [to]} -> if(to =~ "/owner/s/", do: :head_view, else: 302)
        {status, _} -> status
      end
    rescue
      error -> Plug.Exception.status(error)
    end
  end

  defp observe(conn, private?) do
    world = world(private?)

    for {label, template, public, private} <- @matrix do
      expected = if private?, do: private || public, else: public
      path = path_for(template, world)

      actual =
        for viewer <- @viewers,
            do: outcome(conn, world.users[viewer], path)

      {label, template, expected, actual}
    end
  end

  defp report(rows, privacy) do
    if out = System.get_env("PRIVACY_MATRIX_OUT") do
      existing =
        case File.read(out) do
          {:ok, body} -> Jason.decode!(body)
          _ -> %{}
        end

      encoded =
        for {label, template, expected, actual} <- rows do
          %{
            label: label,
            path: template,
            expected: Enum.map(expected, &to_string/1),
            actual: Enum.map(actual, &to_string/1)
          }
        end

      File.write!(
        out,
        Jason.encode!(
          Map.merge(existing, %{
            "viewers" => Enum.map(@viewers, &to_string/1),
            privacy => encoded
          })
        )
      )
    end
  end

  for privacy <- ["public", "private"] do
    test "#{privacy} club: every surface answers each viewer as the matrix says", %{conn: conn} do
      rows = observe(conn, unquote(privacy) == "private")
      report(rows, unquote(privacy))

      mismatches =
        for {label, _template, expected, actual} <- rows,
            {viewer, want, got} <- Enum.zip([@viewers, expected, actual]),
            want != got,
            do: "#{label} as #{viewer}: expected #{want}, got #{got}"

      assert mismatches == [], Enum.join(mismatches, "\n")
    end
  end

  test "a private club never feeds the global standings", %{conn: conn} do
    world = world(true)
    html = conn |> get(~p"/standings/teams") |> html_response(200)
    refute html =~ "Quiet night"
    refute html =~ world.club.name
  end
end
