defmodule CabWeb.GuestLinksTest do
  @moduledoc """
  M6 guest access: the shared /r/:session_uuid registration URL, the
  personal /l/:code link (identity + scope), the owner Registration
  surface and the /api/v1 links twins.
  """

  use CabWeb.ConnCase, async: true

  import Cab.Fixtures
  import Ecto.Query

  alias Cab.Accounts.User
  alias Cab.Links
  alias Cab.Links.Link
  alias Cab.Repo

  setup %{conn: conn} do
    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})
    %{conn: conn, head: head, club: club}
  end

  defp log_in(conn, user) do
    conn
    |> init_test_session(%{user_id: user.id})
    |> Plug.Conn.put_private(:plug_skip_csrf_protection, true)
  end

  defp anon(conn), do: Plug.Conn.put_private(conn, :plug_skip_csrf_protection, true)

  defp stub(fun) do
    Req.Test.stub(Core.Engine, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      params = if body == "", do: %{}, else: Jason.decode!(body)
      fun.(conn, params)
    end)
  end

  defp ok(conn, data), do: Req.Test.json(conn, %{"status" => "success", "data" => data})

  # the stage reads every page needs; `extra` handles writes first
  defp stub_stage(signups, rooms \\ [], extra \\ fn _conn, _params -> nil end) do
    stub(fn conn, params ->
      case extra.(conn, params) do
        nil ->
          case {conn.method, conn.request_path} do
            {"GET", "/api/events/11"} ->
              ok(conn, %{"id" => 11, "name" => "Guest night", "status" => "scheduled"})

            {"GET", "/api/events/11/rounds"} ->
              ok(conn, [%{"id" => 21, "sequence" => 1}])

            {"GET", "/api/events/11/participants"} ->
              ok(conn, signups)

            {"GET", "/api/rounds/21/rooms"} ->
              ok(conn, rooms)
          end

        response ->
          response
      end
    end)
  end

  defp guest_signup(id, user_id, role \\ "speaker", name \\ "Greta Guest") do
    %{"id" => id, "user_id" => user_id, "role" => role, "display_name" => name}
  end

  # ---------------------------------------------------------------
  # Shared registration URL /r/:session_uuid (public)
  # ---------------------------------------------------------------

  describe "shared registration URL" do
    test "serves the form anonymously while :signup", %{conn: conn, club: club} do
      session = session_fixture(club, engine_event_id: 11)
      stub_stage([])

      html = conn |> get(~p"/r/#{session.uuid}") |> html_response(200)

      assert html =~ ~s(id="guest-register-form")
      assert html =~ ~s(action="/r/#{session.uuid}")
      assert html =~ ~s(name="name")
      # no role choice: the head seats people at allocation
      refute html =~ ~s(name="as")
      refute html =~ "Registration is closed"
    end

    test "unknown session is 404", %{conn: conn} do
      assert conn |> get(~p"/r/#{Ecto.UUID.generate()}") |> response(404)
      assert conn |> get("/r/not-a-uuid") |> response(404)
    end

    test "any stage but :signup serves the closed notice", %{conn: conn, club: club} do
      session = closed_session_fixture(club, engine_event_id: 11)
      stub_stage([])

      html = conn |> get(~p"/r/#{session.uuid}") |> html_response(200)
      assert html =~ "Registration is closed for this session."
      refute html =~ ~s(id="guest-register-form")
    end

    test "POST creates guest user + engine signup + link and renders the personal URL",
         %{conn: conn, club: club} do
      session = session_fixture(club, engine_event_id: 11)
      test_pid = self()

      stub_stage([], [], fn conn, params ->
        case {conn.method, conn.request_path} do
          {"POST", "/api/users/register"} ->
            Req.Test.json(conn, %{"token" => Core.Engine.mint_token(777)})

          {"POST", "/api/events/11/participants"} ->
            send(test_pid, {:signup, params})
            ok(conn, %{"id" => 41, "role" => params["role"]})

          _other ->
            nil
        end
      end)

      html =
        conn
        |> anon()
        |> post(~p"/r/#{session.uuid}", %{name: "Greta Guest", as: "speak"})
        |> html_response(200)

      assert_received {:signup,
                       %{"display_name" => "Greta Guest", "role" => "speaker", "user_id" => 777}}

      assert [%Link{} = link] = Repo.all(Link)
      assert link.session_id == session.id
      assert link.club_id == club.id
      assert link.revoked_at == nil
      # >= 24 bytes of url-safe randomness
      assert String.length(link.code) >= 32

      guest = Repo.get!(User, link.user_id)
      assert guest.name == "Greta Guest"
      assert String.starts_with?(guest.username, "guest-")
      assert guest.node_user_id == 777
      # a guest has NO oauth identity
      refute Repo.exists?(from i in Cab.Accounts.Identity, where: i.user_id == ^guest.id)

      assert html =~ "/l/#{link.code}"
      assert html =~ "anyone with it acts as you"
      assert html =~ ~s(data-copy=)
    end

    test "a blank name re-renders the form with the error; nothing is created",
         %{conn: conn, club: club} do
      session = session_fixture(club, engine_event_id: 11)
      stub_stage([])

      html =
        conn
        |> anon()
        |> post(~p"/r/#{session.uuid}", %{name: "   ", as: "speak"})
        |> html_response(422)

      assert html =~ "name is required"
      assert Repo.all(Link) == []
      refute Repo.exists?(from u in User, where: like(u.username, "guest-%"))
    end

    test "POST after close serves the closed notice and leaves no guest rows",
         %{conn: conn, club: club} do
      session = closed_session_fixture(club, engine_event_id: 11)
      stub_stage([])

      html =
        conn
        |> anon()
        |> post(~p"/r/#{session.uuid}", %{name: "Late Larry", as: "speak"})
        |> html_response(200)

      assert html =~ "Registration is closed for this session."
      assert Repo.all(Link) == []
      refute Repo.exists?(from u in User, where: like(u.username, "guest-%"))
    end
  end

  # ---------------------------------------------------------------
  # Personal link /l/:code
  # ---------------------------------------------------------------

  describe "personal link" do
    setup %{club: club} do
      guest = user_fixture(%{node_user_id: 777, name: "Greta Guest", username: "guest-greta"})
      session = session_fixture(club, engine_event_id: 11)
      link = link_fixture(guest, session)
      %{guest: guest, session: session, link: link}
    end

    test "redirects to P6 with the guest identity; removed and unknown codes are 404",
         %{conn: conn, club: club, session: session, link: link} do
      stub_stage([guest_signup(41, 777)])

      conn = get(conn, ~p"/l/#{link.code}")
      assert redirected_to(conn) == "/c/#{club.uuid}/s/#{session.uuid}"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "anyone with it acts as you"

      # P6 greets the guest with their registration + cancel action
      html = conn |> get(~p"/c/#{club.uuid}/s/#{session.uuid}") |> html_response(200)
      assert html =~ "You are registered for tonight."
      assert html =~ "Cancel my registration"
      assert html =~ "/c/#{club.uuid}/s/#{session.uuid}/signups/41/remove"

      assert conn |> get("/l/#{Cab.Links.Link.generate_code()}") |> response(404)

      # a removed guest's account goes, and the link with it
      :ok = Links.purge_guest(777)
      assert conn |> get(~p"/l/#{link.code}") |> response(404)
    end

    test "a signed-in account is never replaced; the link offers to claim the history",
         %{conn: conn, club: club, session: session, link: link, head: head} do
      stub_stage([guest_signup(41, 777)])

      html =
        conn
        |> init_test_session(%{user_id: head.id})
        |> get(~p"/l/#{link.code}")
        |> html_response(200)

      assert html =~ "Add to my account"
      assert html =~ ~s(action="/l/#{link.code}/claim")
      assert html =~ "/c/#{club.uuid}/s/#{session.uuid}"
    end

    test "claiming moves the guest's history onto the account; guest and link are gone",
         %{conn: conn, link: link, guest: guest} do
      account = user_fixture(%{node_user_id: 501, name: "Real Greta"})
      test_pid = self()

      stub_stage([guest_signup(41, 777)], [], fn conn, params ->
        case {conn.method, conn.request_path} do
          {"POST", "/api/admins/merge"} ->
            send(test_pid, {:merge, params, conn})
            ok(conn, %{"moved" => 1})

          _other ->
            nil
        end
      end)

      claimed =
        conn
        |> log_in(account)
        |> post(~p"/l/#{link.code}/claim")

      assert redirected_to(claimed) == "/me"
      assert Phoenix.Flash.get(claimed.assigns.flash, :info) =~ "now on your account"

      assert_received {:merge, params, engine_conn}

      assert params == %{
               "sourceUserId" => 777,
               "targetUserId" => 501,
               "displayName" => "Real Greta"
             }

      ["Bearer " <> token] = Plug.Conn.get_req_header(engine_conn, "authorization")
      {:ok, claims} = Joken.verify(token, Joken.Signer.create("HS256", "test-engine-secret"))
      assert claims["isAdmin"] == true

      assert Repo.get(User, guest.id) == nil
      assert conn |> get(~p"/l/#{link.code}") |> response(404)
    end

    test "an engine refusal keeps everything and says why",
         %{conn: conn, link: link, guest: guest} do
      account = user_fixture(%{node_user_id: 502})

      stub_stage([guest_signup(41, 777)], [], fn conn, _params ->
        case {conn.method, conn.request_path} do
          {"POST", "/api/admins/merge"} ->
            conn
            |> Plug.Conn.put_resp_content_type("application/json")
            |> Plug.Conn.send_resp(
              409,
              ~s({"status":"fail","message":"Both users are registered in event 11"})
            )

          _other ->
            nil
        end
      end)

      refused = conn |> log_in(account) |> post(~p"/l/#{link.code}/claim")
      assert Phoenix.Flash.get(refused.assigns.flash, :error) =~ "event 11"
      assert Repo.get(User, guest.id)
    end

    test "/account claims a pasted personal link; nonsense is refused in words",
         %{conn: conn, link: link, guest: guest} do
      account = user_fixture(%{node_user_id: 503})

      stub_stage([guest_signup(41, 777)], [], fn conn, _params ->
        case {conn.method, conn.request_path} do
          {"POST", "/api/admins/merge"} -> ok(conn, %{"moved" => 1})
          _other -> nil
        end
      end)

      html = conn |> log_in(account) |> get(~p"/account") |> html_response(200)
      assert html =~ ~s(action="/account/claim")

      bad = conn |> log_in(account) |> post(~p"/account/claim", %{link: "nonsense"})
      assert Phoenix.Flash.get(bad.assigns.flash, :error) =~ "does not exist"

      done =
        conn
        |> log_in(account)
        |> post(~p"/account/claim", %{link: "https://cab.uadebate.com/l/#{link.code}"})

      assert redirected_to(done) == "/me"
      assert Repo.get(User, guest.id) == nil
    end

    test "a guest identity cannot claim another guest's history",
         %{conn: conn, link: link} do
      other = user_fixture(%{node_user_id: 889, username: "guest-other"})
      session = Cab.Repo.preload(link, :session).session
      link_fixture(other, session)
      stub_stage([guest_signup(41, 777)])

      refused = conn |> log_in(other) |> post(~p"/l/#{link.code}/claim")
      assert Phoenix.Flash.get(refused.assigns.flash, :error) =~ "your own account"
    end

    test "a guest device may switch to another guest's link",
         %{conn: conn, club: club, session: session, link: link} do
      stub_stage([guest_signup(41, 777)])
      other = user_fixture(%{node_user_id: 778, username: "guest-other"})
      _other_link = link_fixture(other, session)

      conn = conn |> init_test_session(%{user_id: other.id}) |> get(~p"/l/#{link.code}")

      assert redirected_to(conn) == "/c/#{club.uuid}/s/#{session.uuid}"
      assert Plug.Conn.get_session(conn, :user_id) == link.user_id
    end

    test "link identity never satisfies the signed-in trees or the owner API",
         %{conn: conn, club: club, session: session, link: link, guest: guest} do
      stub_stage([guest_signup(41, 777)])

      conn = get(conn, ~p"/l/#{link.code}")
      assert redirected_to(conn) == "/c/#{club.uuid}/s/#{session.uuid}"
      # the browser session now carries the guest identity ...
      assert Plug.Conn.get_session(conn, :user_id) == guest.id

      # ... which opens NOTHING beyond P6's public view
      {:ok, private} = Cab.Clubs.update_club(club, %{"is_private" => "true"})
      assert conn |> get(~p"/c/#{private.uuid}/members") |> response(403)
      assert conn |> get(~p"/c/#{club.uuid}/owner") |> response(403)
      assert_error_sent 403, fn -> get(conn, ~p"/c/#{club.uuid}/owner/s/#{session.uuid}") end

      denied = get(conn, ~p"/api/v1/sessions/#{session.uuid}/links")
      assert json_response(denied, 403)["error"] == "forbidden"
    end

    test "guest cancels their own registration through P6 while :signup",
         %{conn: conn, club: club, session: session, link: link} do
      test_pid = self()

      stub_stage([guest_signup(41, 777)], [], fn conn, params ->
        case {conn.method, conn.request_path} do
          {"PUT", "/api/events/11/participants/41"} ->
            send(test_pid, {:renamed, params["display_name"]})
            ok(conn, %{})

          {"DELETE", "/api/events/11/participants/41"} ->
            send(test_pid, :removed)
            Req.Test.json(conn, %{"status" => "success", "message" => "Participant archived."})

          _other ->
            nil
        end
      end)

      conn = get(conn, ~p"/l/#{link.code}")

      conn =
        conn |> anon() |> post(~p"/c/#{club.uuid}/s/#{session.uuid}/signups/41/remove")

      assert redirected_to(conn) == "/c/#{club.uuid}/s/#{session.uuid}"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "registration cancelled"
      assert_received {:renamed, "removed"}
      assert_received :removed

      # nothing personal stays: the guest account and its link are gone
      assert Repo.get(User, link.user_id) == nil
      assert conn |> get(~p"/l/#{link.code}") |> response(404)
    end

    test "guest cannot cancel someone else's signup",
         %{conn: conn, club: club, session: session, link: link} do
      stub_stage([guest_signup(41, 777), guest_signup(42, 888, "speaker", "Other")])

      conn = get(conn, ~p"/l/#{link.code}")
      conn = conn |> anon() |> post(~p"/c/#{club.uuid}/s/#{session.uuid}/signups/42/remove")
      assert response(conn, 403)
    end

    test "anonymous cancel hits the auth wall", %{conn: conn, club: club, session: session} do
      stub_stage([guest_signup(41, 777)])

      conn = conn |> anon() |> post(~p"/c/#{club.uuid}/s/#{session.uuid}/signups/41/remove")
      assert redirected_to(conn) == "/signin"
    end
  end

  # ---------------------------------------------------------------
  # Guest judge ballot under /l/:code
  # ---------------------------------------------------------------

  # a judging room 71 chaired by engine user `chair_user_id`
  defp running_room(chair_user_id) do
    %{
      "id" => 71,
      "status" => "judging",
      "Motion" => %{"motion_text" => "THW trust guests"},
      "RoomAdjudicators" => [
        %{
          "id" => 1,
          "role" => "chair",
          "EventParticipant" => %{"id" => 90, "user_id" => chair_user_id}
        }
      ],
      "RoomTeams" =>
        for position <- 1..4 do
          %{
            "id" => 100 + position,
            "position" => position,
            "Team" => %{"name" => "Team #{position}"},
            "RoomSpeakers" =>
              for n <- [1, 2] do
                %{
                  "id" => 200 + position * 2 - 2 + n,
                  "EventParticipant" => %{
                    "id" => 300 + position * 2 - 2 + n,
                    "display_name" => "Speaker #{position}.#{n}"
                  }
                }
              end
          }
        end
    }
  end

  defp ballot_params do
    %{
      "ballot" => %{
        "og" => %{
          "PM" => %{"speaker" => "301", "score" => "78"},
          "DPM" => %{"speaker" => "302", "score" => "76"}
        },
        "oo" => %{
          "LO" => %{"speaker" => "303", "score" => "76"},
          "DLO" => %{"speaker" => "304", "score" => "75"}
        },
        "cg" => %{
          "MG" => %{"speaker" => "305", "score" => "74"},
          "GW" => %{"speaker" => "306", "score" => "75"}
        },
        "co" => %{
          "MO" => %{"speaker" => "307", "score" => "72"},
          "OW" => %{"speaker" => "308", "score" => "75"}
        }
      }
    }
  end

  describe "guest judge ballot" do
    setup %{club: club} do
      guest = user_fixture(%{node_user_id: 777, name: "Judge Judy", username: "guest-judy"})
      session = session_fixture(club, engine_event_id: 11)
      link = link_fixture(guest, session)
      %{guest: guest, session: session, link: link}
    end

    test "the chair guest sees Fill ballot on P6, gets the page and submits",
         %{conn: conn, club: club, session: session, link: link} do
      test_pid = self()

      stub_stage(
        [guest_signup(90, 777, "adjudicator", "Judge Judy")],
        [running_room(777)],
        fn conn, params ->
          case {conn.method, conn.request_path} do
            {"POST", "/api/rooms/71/scores"} ->
              send(test_pid, {:scores, params})
              Req.Test.json(conn, %{"status" => "success", "message" => "ok"})

            {"PATCH", "/api/rooms/71/confirm"} ->
              send(test_pid, :confirmed)
              Req.Test.json(conn, %{"status" => "success", "message" => "ok"})

            _other ->
              nil
          end
        end
      )

      # the personal link lands on P6 with the guest identity
      conn = get(conn, ~p"/l/#{link.code}")
      assert redirected_to(conn) == "/c/#{club.uuid}/s/#{session.uuid}"

      home = conn |> get(~p"/c/#{club.uuid}/s/#{session.uuid}") |> html_response(200)
      assert home =~ "Fill ballot"
      assert home =~ "/c/#{club.uuid}/s/#{session.uuid}/rooms/71/ballot"

      html =
        conn
        |> get(~p"/c/#{club.uuid}/s/#{session.uuid}/rooms/71/ballot")
        |> html_response(200)

      assert html =~ ~s(class="ballot")
      assert html =~ "THW trust guests"
      assert html =~ ~s(action="/c/#{club.uuid}/s/#{session.uuid}/rooms/71/ballot")
      assert html =~ ~s(form="ballot-71")

      done =
        conn
        |> anon()
        |> post(~p"/c/#{club.uuid}/s/#{session.uuid}/rooms/71/ballot", ballot_params())

      assert redirected_to(done) == "/c/#{club.uuid}/s/#{session.uuid}"
      assert Phoenix.Flash.get(done.assigns.flash, :info) =~ "ballot submitted"
      assert_received {:scores, params}
      assert [%{"rank" => 1, "room_team_id" => 101} | _rest] = params["teamRankings"]
      assert_received :confirmed
    end

    test "a guest who is not the chair gets 403; a foreign room is 404",
         %{conn: conn, club: club, session: session, link: link} do
      stub_stage([guest_signup(41, 777)], [running_room(555)])

      conn = get(conn, ~p"/l/#{link.code}")

      assert conn
             |> get(~p"/c/#{club.uuid}/s/#{session.uuid}/rooms/71/ballot")
             |> response(403)

      assert conn
             |> anon()
             |> post(~p"/c/#{club.uuid}/s/#{session.uuid}/rooms/71/ballot", ballot_params())
             |> response(403)

      assert conn
             |> get(~p"/c/#{club.uuid}/s/#{session.uuid}/rooms/99/ballot")
             |> response(404)
    end
  end

  # ---------------------------------------------------------------
  # Owner surface: add a person, one people table, remove
  # ---------------------------------------------------------------

  describe "owner registration surface" do
    test "owner page: the shared URL, the add form and one people table",
         %{conn: conn, club: club, head: head} do
      guest = user_fixture(%{node_user_id: 777, name: "Greta Guest", username: "guest-greta"})
      session = session_fixture(club, engine_event_id: 11)
      link = link_fixture(guest, session)
      stub_stage([guest_signup(41, 777)])

      html =
        conn
        |> log_in(head)
        |> get(~p"/c/#{club.uuid}/owner/s/#{session.uuid}")
        |> html_response(200)

      assert html =~ ~s(id="shared-registration-url")
      assert html =~ "/r/#{session.uuid}"
      assert html =~ ~s(data-copy=)

      # guests and everyone else share one table: kind, seat, link, remove
      assert html =~ ~s(id="session-people")
      assert html =~ "People (1 person)"
      assert html =~ "Greta Guest"
      assert html =~ "guest"
      assert html =~ "not placed"
      assert html =~ link.code
      assert html =~ "/c/#{club.uuid}/owner/sessions/#{session.uuid}/signups/41/remove"
      refute html =~ "revoke"
      refute html =~ ~s(id="guest-links")

      # one add form: a member from the list, or a guest by name
      assert html =~ ~s(id="add-person-form")
      assert html =~ ~s(name="username")
      assert html =~ ~s(name="name")
    end

    test "owner removes a guest: the name is scrubbed, account and link are gone",
         %{conn: conn, club: club, head: head} do
      guest = user_fixture(%{node_user_id: 777, name: "Greta Guest"})
      session = session_fixture(club, engine_event_id: 11)
      link = link_fixture(guest, session)
      test_pid = self()

      stub_stage([guest_signup(41, 777)], [], fn conn, params ->
        case {conn.method, conn.request_path} do
          {"PUT", "/api/events/11/participants/41"} ->
            send(test_pid, {:renamed, params["display_name"]})
            ok(conn, %{})

          {"DELETE", "/api/events/11/participants/41"} ->
            Req.Test.json(conn, %{"status" => "success"})

          _other ->
            nil
        end
      end)

      removed =
        conn
        |> log_in(head)
        |> post(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/signups/41/remove")

      assert redirected_to(removed) == "/c/#{club.uuid}/owner/s/#{session.uuid}"
      assert_received {:renamed, "removed"}
      assert Repo.get(User, guest.id) == nil
      assert Links.get_active_by_code(link.code) == nil
    end

    test "owner adds a guest by name; the flash carries the personal URL",
         %{conn: conn, club: club, head: head} do
      session = session_fixture(club, engine_event_id: 11)
      test_pid = self()

      stub_stage([], [], fn conn, params ->
        case {conn.method, conn.request_path} do
          {"POST", "/api/users/register"} ->
            Req.Test.json(conn, %{"token" => Core.Engine.mint_token(778)})

          {"POST", "/api/events/11/participants"} ->
            send(test_pid, {:signup, params})
            ok(conn, %{"id" => 42, "role" => params["role"]})

          _other ->
            nil
        end
      end)

      added =
        conn
        |> log_in(head)
        |> post(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/signups", %{
          username: "",
          name: "Handed Hanna"
        })

      assert redirected_to(added) == "/c/#{club.uuid}/owner/s/#{session.uuid}"
      assert_received {:signup, %{"role" => "speaker", "user_id" => 778}}

      assert [link] = Links.list_for_session(session)
      assert Phoenix.Flash.get(added.assigns.flash, :info) =~ "/l/#{link.code}"

      # neither or both is refused with words
      neither =
        conn
        |> log_in(head)
        |> post(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/signups", %{
          username: "",
          name: ""
        })

      assert Phoenix.Flash.get(neither.assigns.flash, :error) =~ "pick a member or type"
    end
  end

  # ---------------------------------------------------------------
  # API twins
  # ---------------------------------------------------------------

  describe "links API" do
    test "index: 401 anonymous, 403 member, 200 head with roles",
         %{conn: conn, club: club, head: head} do
      guest = user_fixture(%{node_user_id: 777, name: "Greta Guest"})
      session = session_fixture(club, engine_event_id: 11)
      link = link_fixture(guest, session)
      stub_stage([guest_signup(41, 777)])

      assert conn
             |> get(~p"/api/v1/sessions/#{session.uuid}/links")
             |> json_response(401)

      member = user_fixture()
      membership_fixture(member, club)

      assert conn
             |> log_in(member)
             |> get(~p"/api/v1/sessions/#{session.uuid}/links")
             |> json_response(403)

      body =
        conn
        |> log_in(head)
        |> get(~p"/api/v1/sessions/#{session.uuid}/links")
        |> json_response(200)

      assert [entry] = body["links"]
      assert entry["name"] == "Greta Guest"
      assert entry["role"] == "speaker"
      assert entry["code"] == link.code
      assert entry["url"] =~ "/l/#{link.code}"
    end

    test "create: head issues a guest link; members may not",
         %{conn: conn, club: club, head: head} do
      session = session_fixture(club, engine_event_id: 11)

      stub_stage([], [], fn conn, params ->
        case {conn.method, conn.request_path} do
          {"POST", "/api/users/register"} ->
            Req.Test.json(conn, %{"token" => Core.Engine.mint_token(779)})

          {"POST", "/api/events/11/participants"} ->
            ok(conn, %{"id" => 43, "role" => params["role"]})

          _other ->
            nil
        end
      end)

      member = user_fixture()
      membership_fixture(member, club)

      assert conn
             |> log_in(member)
             |> post(~p"/api/v1/sessions/#{session.uuid}/links", %{name: "X"})
             |> json_response(403)

      body =
        conn
        |> log_in(head)
        |> post(~p"/api/v1/sessions/#{session.uuid}/links", %{name: "Api Anna"})
        |> json_response(201)

      assert body["name"] == "Api Anna"
      assert body["url"] =~ "/l/"
      assert [_link] = Links.list_for_session(session)
    end

    test "create without a name is 422; after close it is 409",
         %{conn: conn, club: club, head: head} do
      session = closed_session_fixture(club, engine_event_id: 11)
      stub_stage([])

      assert conn
             |> log_in(head)
             |> post(~p"/api/v1/sessions/#{session.uuid}/links", %{name: ""})
             |> json_response(422)

      conflict =
        conn
        |> log_in(head)
        |> post(~p"/api/v1/sessions/#{session.uuid}/links", %{name: "Late"})
        |> json_response(409)

      assert conflict["error"] =~ "sign-ups are not open"
    end

    test "a guest leaves through DELETE signups: link dead, account gone",
         %{conn: conn, club: club, head: head} do
      guest = user_fixture(%{node_user_id: 777, name: "Greta Guest"})
      session = session_fixture(club, engine_event_id: 11)
      link = link_fixture(guest, session)

      stub_stage([guest_signup(41, 777)], [], fn conn, _params ->
        case {conn.method, conn.request_path} do
          {"PUT", "/api/events/11/participants/41"} ->
            ok(conn, %{})

          {"DELETE", "/api/events/11/participants/41"} ->
            Req.Test.json(conn, %{"status" => "success"})

          _other ->
            nil
        end
      end)

      body =
        conn
        |> log_in(head)
        |> delete(~p"/api/v1/sessions/#{session.uuid}/signups/41")
        |> json_response(200)

      assert body["status"] == "removed"
      assert Repo.get(User, guest.id) == nil
      assert conn |> get(~p"/l/#{link.code}") |> response(404)
    end
  end
end
