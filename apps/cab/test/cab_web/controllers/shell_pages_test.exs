defmodule CabWeb.ShellPagesTest do
  @moduledoc """
  M8a shell acceptance: the sidenav per context, /account, /admin
  (permissions, create club, change head, archive hiding) and the
  GLOBAL standings tabs (rule-0 passthrough).
  """

  use CabWeb.ConnCase, async: true

  import Cab.Fixtures

  defp log_in(conn, user) do
    conn
    |> init_test_session(%{user_id: user.id})
    |> Plug.Conn.put_private(:plug_skip_csrf_protection, true)
  end

  defp stub(fun) do
    Req.Test.stub(Core.Engine, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      params = if body == "", do: %{}, else: Jason.decode!(body)
      fun.(conn, params)
    end)
  end

  defp ok(conn, data), do: Req.Test.json(conn, %{"status" => "success", "data" => data})

  defp admin_fixture(attrs \\ %{}) do
    user = user_fixture(attrs)
    user |> Ecto.Changeset.change(is_admin: true) |> Cab.Repo.update!()
  end

  # ---------------------------------------------------------------
  # Sidenav per context
  # ---------------------------------------------------------------

  describe "sidenav" do
    test "global context: Clubs + Standings; Admin only for admins", %{conn: conn} do
      html = conn |> get(~p"/") |> html_response(200)

      assert html =~ ~s(id="sidenav")
      assert html =~ ">Clubs<"
      assert html =~ ~s(href="/standings/teams")
      refute html =~ ">Admin<"
      # anonymous profile block: Sign in only
      assert html =~ ~s(id="sidenav-profile")
      assert html =~ "Sign in"
      refute html =~ ~s(href="/account")
      refute html =~ ">My page<"

      Req.Test.stub(Core.Engine, fn req ->
        case req.request_path do
          "/api/users/schedule" ->
            Req.Test.json(req, %{
              "status" => "success",
              "data" => %{"as_adjudicator" => [], "as_player" => []}
            })
        end
      end)

      user_html = conn |> log_in(user_fixture()) |> get(~p"/") |> html_response(200)
      refute user_html =~ ">Admin<"
      assert user_html =~ ~s(href="/account")
      assert user_html =~ "Sign out"

      admin_html = conn |> log_in(admin_fixture()) |> get(~p"/") |> html_response(200)
      assert admin_html =~ ">Admin<"
      assert admin_html =~ ~s(href="/admin")
    end

    test "club context: the place items, role-scoped", %{conn: conn} do
      head = user_fixture(%{node_user_id: 9})
      club = club_fixture(head, %{engine_organisation_id: 3})
      session = session_fixture(club, engine_event_id: 11)

      stub(fn conn, _params ->
        case conn.request_path do
          "/api/events/organisation/3" ->
            ok(conn, [%{"id" => 11, "name" => "Tonight", "status" => "scheduled"}])
        end
      end)

      html = conn |> get(~p"/c/#{club.uuid}") |> html_response(200)

      assert html =~ club.name

      for item <- ~w(Club Rooms Standings Members Register) do
        assert html =~ ">#{item}<"
      end

      # the Sessions item is gone - the club page is the archive
      refute html =~ ">Sessions<"

      # public: Rooms -> the session page; the roster behind the wall;
      # Register -> THE registration URL
      assert html =~ ~s(href="/c/#{club.uuid}/s/#{session.uuid}")
      assert html =~ ~s(href="/c/#{club.uuid}/standings/teams")
      assert html =~ ~s(href="/c/#{club.uuid}/members")
      assert html =~ ~s(href="/r/#{session.uuid}")

      # the owner's sidenav targets the owner trees
      owner_html = conn |> log_in(head) |> get(~p"/c/#{club.uuid}") |> html_response(200)
      assert owner_html =~ ~s(href="/c/#{club.uuid}/owner/s/#{session.uuid}")
      assert owner_html =~ ~s(href="/c/#{club.uuid}/owner/members")
      assert owner_html =~ ~s(href="/c/#{club.uuid}/owner")

      # no badges/counters anywhere in the sidenav
      refute html =~ ~s(class="n")
    end
  end

  # ---------------------------------------------------------------
  # /account
  # ---------------------------------------------------------------

  describe "/account" do
    test "anonymous is walled to /signin", %{conn: conn} do
      assert conn |> get(~p"/account") |> redirected_to() == "/signin"
    end

    test "shows the profile and saves the display name", %{conn: conn} do
      user = user_fixture(%{username: "anna"})

      html = conn |> log_in(user) |> get(~p"/account") |> html_response(200)

      assert html =~ ~s(id="account-form")
      assert html =~ ~s(name="name")
      assert html =~ "anna"
      # Save drives the form from the chrome; sign out at hand
      assert html =~ ~s(form="account-form")
      assert html =~ "Save"
      assert html =~ ~s(href="/auth/logout")

      saved = conn |> log_in(user) |> post(~p"/account", %{name: "Anna Kovalenko"})
      assert redirected_to(saved) == "/account"
      assert Cab.Accounts.get_user(user.id).name == "Anna Kovalenko"
    end
  end

  # ---------------------------------------------------------------
  # /admin
  # ---------------------------------------------------------------

  describe "/admin" do
    test "404 for anonymous and plain users - the page does not exist for them",
         %{conn: conn} do
      assert conn |> get(~p"/admin") |> response(404)
      assert conn |> log_in(user_fixture()) |> get(~p"/admin") |> response(404)
      assert conn |> log_in(user_fixture()) |> post(~p"/admin/clubs") |> response(404)
    end

    test "clubs table + create-club form + change-head form", %{conn: conn} do
      admin = admin_fixture()
      head = user_fixture(%{username: "oldhead", name: "Old Head"})
      club = club_fixture(head, %{city: "Kyiv"})

      html = conn |> log_in(admin) |> get(~p"/admin") |> html_response(200)

      assert html =~ ~s(id="admin-clubs")
      assert html =~ club.name
      assert html =~ "Kyiv"
      assert html =~ "Old Head"
      assert html =~ "live"
      assert html =~ "/admin/clubs/#{club.uuid}/archive"

      assert html =~ ~s(id="create-club-form")
      assert html =~ ~s(form="create-club-form")
      assert html =~ "Create club"
      assert html =~ ~s(id="change-head-form")
      # one gold action: Create club in the chrome; the other forms' buttons are plain
      refute html =~ ~s(class="btn-go")
      assert html =~ ~s(id="merge-accounts-form")
    end

    test "creates a club through the engine", %{conn: conn} do
      admin = admin_fixture()
      head = user_fixture(%{node_user_id: 9, username: "newhead"})

      stub(fn conn, params ->
        assert conn.method == "POST"
        assert conn.request_path == "/api/organisations"
        assert params["owner_id"] == 9
        ok(conn, %{"id" => 3, "name" => params["name"]})
      end)

      created =
        conn
        |> log_in(admin)
        |> post(~p"/admin/clubs", %{name: "Admin Club", city: "Kyiv", head: head.username})

      assert redirected_to(created) == "/admin"
      assert [club] = Cab.Clubs.list_clubs() |> Enum.filter(&(&1.name == "Admin Club"))
      assert Cab.Clubs.role_for(club, head) == :owner
    end

    test "changes the head", %{conn: conn} do
      admin = admin_fixture()
      old_head = user_fixture(%{node_user_id: 9})
      new_head = user_fixture(%{node_user_id: 10, username: "fresh"})
      club = club_fixture(old_head, %{engine_organisation_id: 3})

      stub(fn conn, params ->
        assert conn.request_path =~ "/api/organisations/3/owners"
        if conn.method == "POST", do: assert(params["targetUserId"] == 10)
        ok(conn, %{"id" => 1})
      end)

      changed =
        conn
        |> log_in(admin)
        |> post(~p"/admin/head", %{uuid: club.uuid, head: new_head.username})

      assert redirected_to(changed) == "/admin"
      assert Cab.Clubs.role_for(club, new_head) == :owner
      assert Cab.Clubs.role_for(club, old_head) == :member
    end

    test "archive hides the club everywhere public, admin still sees it", %{conn: conn} do
      admin = admin_fixture()
      head = user_fixture(%{node_user_id: 9})
      club = club_fixture(head, %{name: "Soon Gone #{System.unique_integer([:positive])}"})

      archived = conn |> log_in(admin) |> post(~p"/admin/clubs/#{club.uuid}/archive")
      assert redirected_to(archived) == "/admin"

      # gone from the directory and every public page - a plain 404
      front = conn |> get(~p"/") |> html_response(200)
      refute front =~ club.name
      assert conn |> get(~p"/c/#{club.uuid}") |> response(404)
      assert conn |> get(~p"/c/#{club.uuid}/standings/teams") |> response(404)
      assert conn |> log_in(head) |> get(~p"/c/#{club.uuid}") |> response(404)

      # the admin table still lists it, as words
      admin_html = conn |> log_in(admin) |> get(~p"/admin") |> html_response(200)
      assert admin_html =~ club.name
      assert admin_html =~ "archived"
    end
  end

  # ---------------------------------------------------------------
  # /standings - global tabs, rule-0 passthrough
  # ---------------------------------------------------------------

  describe "/standings" do
    setup %{conn: conn} do
      head = user_fixture(%{node_user_id: 9})
      club = club_fixture(head, %{engine_organisation_id: 3})

      session =
        session_fixture(club,
          engine_event_id: 11,
          name: "Thursday practice",
          finished_at: ~U[2026-10-08 20:00:00Z],
          rooms_count: 1
        )

      %{conn: conn, club: club, session: session}
    end

    test "four public tabs; teams/speakers verbatim engine output", %{conn: conn, club: club} do
      stub(fn conn, _params ->
        case conn.request_path do
          "/api/events/11" ->
            ok(conn, %{"id" => 11, "name" => "Thursday practice", "status" => "completed"})

          "/api/events/11/standings/calculated/teams" ->
            ok(conn, [%{"id" => 1, "name" => "Anna & Bohdan", "total_points" => 3}])

          "/api/events/11/standings/calculated/speakers" ->
            ok(conn, [%{"id" => 7, "name" => "Anna Kovalenko", "total_points" => 101.53}])

          "/api/events/11/stats/adjudicators" ->
            ok(conn, [
              %{"id" => 90, "name" => "Petro", "rooms_adjudicated" => 1, "avg_feedback" => nil}
            ])

          "/api/events/11/rounds" ->
            ok(conn, [%{"id" => 21, "sequence" => 1}])

          "/api/rounds/21/rooms" ->
            ok(conn, [
              %{
                "id" => 71,
                "RoomAdjudicators" => [
                  %{"role" => "chair", "EventParticipant" => %{"display_name" => "Petro"}}
                ]
              }
            ])
        end
      end)

      # the bare URL redirects to the teams tab
      assert conn |> get(~p"/standings") |> redirected_to() == "/standings/teams"

      html = conn |> get(~p"/standings/teams") |> html_response(200)
      assert html =~ ~s(id="standings-tabs")

      for tab <- ~w(teams speakers adjudicators clubs) do
        assert html =~ ~s(href="/standings/#{tab}")
      end

      assert html =~ ~s(id="standings-teams")
      assert html =~ "Anna &amp; Bohdan"
      assert html =~ "Thursday practice"

      speakers = conn |> get(~p"/standings/speakers") |> html_response(200)
      assert speakers =~ "Anna Kovalenko"
      assert speakers =~ "101.53"

      judges = conn |> get(~p"/standings/adjudicators") |> html_response(200)
      assert judges =~ "Petro"
      assert judges =~ "Rooms adjudicated"

      clubs = conn |> get(~p"/standings/clubs") |> html_response(200)
      assert clubs =~ ~s(id="standings-clubs")
      assert clubs =~ club.name

      # rule 0 honesty: no cab-side aggregates anywhere
      for page <- [html, speakers, judges, clubs] do
        refute page =~ "wins"
        refute page =~ "Wins"
        refute page =~ "Win rate"
        refute page =~ "played"
      end

      # an unknown tab is 404
      assert conn |> get("/standings/wins") |> response(404)
    end

    test "no finished session yet shows the notice", %{conn: conn, session: session} do
      # the only session reopens as unfinished in cab's records
      session |> Ecto.Changeset.change(finished_at: nil) |> Cab.Repo.update!()

      html = conn |> get(~p"/standings/teams") |> html_response(200)
      assert html =~ "No finished session yet."
    end
  end
end
