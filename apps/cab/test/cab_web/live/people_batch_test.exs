defmodule CabWeb.PeopleBatchTest do
  @moduledoc """
  The owner session page's People list: check rows (or all of them),
  copy the checked guests' personal links, remove the checked people
  in one go - and the JSON twin, POST .../signups/remove.
  """
  # the owner page is a LiveView in its own process: the engine stub
  # is shared, so this module runs synchronously
  use CabWeb.ConnCase, async: false

  import Cab.Fixtures
  import Phoenix.LiveViewTest

  alias Cab.Accounts.User
  alias Cab.Repo

  setup %{conn: conn} do
    Req.Test.set_req_test_to_shared()
    on_exit(fn -> Req.Test.set_req_test_to_private() end)

    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})
    member = user_fixture(%{node_user_id: 44, name: "Mila Member"})
    membership_fixture(member, club)
    session = session_fixture(club, engine_event_id: 11)

    greta = user_fixture(%{node_user_id: nil, name: "Greta Guest"})
    hugo = user_fixture(%{node_user_id: nil, name: "Hugo Guest"})
    greta_link = link_fixture(greta, session, participant_id: 41)
    hugo_link = link_fixture(hugo, session, participant_id: 42)

    signups = [
      %{"id" => 41, "user_id" => nil, "role" => "speaker", "display_name" => "Greta Guest"},
      %{"id" => 42, "user_id" => nil, "role" => "speaker", "display_name" => "Hugo Guest"},
      %{"id" => 43, "user_id" => 44, "role" => "speaker", "display_name" => "Mila Member"}
    ]

    %{
      conn: conn,
      head: head,
      club: club,
      member: member,
      session: session,
      signups: signups,
      greta: greta,
      greta_link: greta_link,
      hugo_link: hugo_link
    }
  end

  defp ok(conn, data), do: Req.Test.json(conn, %{"status" => "success", "data" => data})

  # the engine answers from an Agent: a removal takes the person out,
  # so the next read (and the page) no longer has them
  defp stub_engine(signups, rooms \\ []) do
    {:ok, agent} = Agent.start_link(fn -> %{signups: signups, rooms: rooms, deleted: []} end)

    Req.Test.stub(Core.Engine, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/11"} ->
          ok(conn, %{"id" => 11, "name" => "Batch night", "status" => "scheduled"})

        {"GET", "/api/events/11/rounds"} ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        {"GET", "/api/events/11/participants"} ->
          ok(conn, Agent.get(agent, & &1.signups))

        {"GET", "/api/rounds/21/rooms"} ->
          ok(conn, Agent.get(agent, & &1.rooms))

        {"PUT", "/api/events/11/participants/" <> _id} ->
          ok(conn, %{})

        {"DELETE", "/api/events/11/participants/" <> id} ->
          id = String.to_integer(id)

          Agent.update(agent, fn world ->
            %{
              world
              | signups: Enum.reject(world.signups, &(&1["id"] == id)),
                deleted: world.deleted ++ [id]
            }
          end)

          Req.Test.json(conn, %{"status" => "success"})
      end
    end)

    agent
  end

  defp seated(id) do
    %{
      "id" => 71,
      "status" => "pending",
      "RoomTeams" => [%{"RoomSpeakers" => [%{"EventParticipant" => %{"id" => id}}]}],
      "RoomAdjudicators" => []
    }
  end

  defp log_in(conn, user) do
    conn
    |> init_test_session(%{user_id: user.id})
    |> Plug.Conn.put_private(:plug_skip_csrf_protection, true)
  end

  defp page(conn, user, club, session) do
    {:ok, view, _html} = conn |> log_in(user) |> live(~p"/c/#{club.uuid}/owner/s/#{session.uuid}")
    view
  end

  defp copied_text(view) do
    [_, text] = Regex.run(~r/id="copy-links"[^>]*data-links="([^"]*)"/, render(view))
    text |> String.replace("&amp;", "&") |> String.split("\n")
  end

  describe "selection and Copy links" do
    test "a checkbox per row and Select all; the bar shows once something is checked",
         %{conn: conn, head: head, club: club, session: session, signups: signups} do
      stub_engine(signups)
      view = page(conn, head, club, session)

      html = render(view)
      assert html =~ ~s(phx-click="toggle")
      assert html =~ ~s(aria-label="Select Greta Guest")
      assert html =~ ~s(aria-label="Select all")
      assert html =~ ~s(class="batch idle")
      refute has_element?(view, "#copy-links")

      view |> element(~s(#session-people input[phx-value-id="41"])) |> render_click()
      assert has_element?(view, "#people-batch .count", "1 selected")
      assert has_element?(view, "#copy-links", "Copy links")
      assert has_element?(view, "#people-batch button", "Remove selected")
      assert has_element?(view, "#people-batch button", "Clear")

      # the page keeps its one gold action
      refute render(view) =~ ~s(class="btn-go")

      view |> element("#session-people thead input.pick") |> render_click()
      assert has_element?(view, "#people-batch .count", "3 selected")

      # Select all again, with everyone checked, clears
      view |> element("#session-people thead input.pick") |> render_click()
      refute has_element?(view, "#copy-links")

      view |> element("#session-people thead input.pick") |> render_click()
      view |> element("#people-batch button", "Clear") |> render_click()
      refute has_element?(view, "#copy-links")
    end

    test "copies one line per checked guest; members have no link and are counted",
         %{
           conn: conn,
           head: head,
           club: club,
           session: session,
           signups: signups,
           greta_link: greta_link,
           hugo_link: hugo_link
         } do
      stub_engine(signups)
      view = page(conn, head, club, session)
      view |> element("#session-people thead input.pick") |> render_click()

      assert copied_text(view) == [
               "Greta Guest - " <> url(~p"/l/#{greta_link.code}"),
               "Hugo Guest - " <> url(~p"/l/#{hugo_link.code}")
             ]

      view |> element("#copy-links") |> render_hook("links_copied", %{"ok" => true})
      assert render(view) =~ "Copied 2 links; 1 person has no personal link."

      # only the guest checked: no missing count
      view |> element("#people-batch button", "Clear") |> render_click()
      view |> element(~s(#session-people input[phx-value-id="42"])) |> render_click()
      assert copied_text(view) == ["Hugo Guest - " <> url(~p"/l/#{hugo_link.code}")]
      view |> element("#copy-links") |> render_hook("links_copied", %{"ok" => true})
      assert render(view) =~ "Copied 1 link."

      # the browser refused the clipboard
      view |> element("#copy-links") |> render_hook("links_copied", %{"ok" => false})
      assert render(view) =~ "This browser did not let us copy."
    end
  end

  describe "Remove selected" do
    test "asks first, then removes everyone checked",
         %{conn: conn, head: head, club: club, session: session, signups: signups, greta: greta} do
      agent = stub_engine(signups)
      view = page(conn, head, club, session)

      view |> element(~s(#session-people input[phx-value-id="41"])) |> render_click()
      view |> element(~s(#session-people input[phx-value-id="43"])) |> render_click()
      view |> element("#people-batch button", "Remove selected") |> render_click()

      assert has_element?(view, "#confirm-remove", "Remove 2 people from Batch night?")
      assert Agent.get(agent, & &1.deleted) == []

      view |> element("#confirm-remove button", "Cancel") |> render_click()
      refute has_element?(view, "#confirm-remove")

      view |> element("#people-batch button", "Remove selected") |> render_click()
      view |> element("#confirm-remove button", "Remove") |> render_click()

      assert Agent.get(agent, & &1.deleted) == [41, 43]
      html = render(view)
      assert html =~ "Removed 2 people."
      refute html =~ "Greta Guest"
      assert html =~ "Hugo Guest"
      refute has_element?(view, "#remove-refused")
      refute has_element?(view, "#copy-links")
      # a removed guest's account goes, as with the single remove
      assert Repo.get(User, greta.id) == nil
    end

    test "partial: whoever can go goes, the rest are listed with the reason",
         %{conn: conn, head: head, club: club, session: session, signups: signups} do
      agent = stub_engine(signups, [seated(42)])
      view = page(conn, head, club, session)

      view |> element("#session-people thead input.pick") |> render_click()
      view |> element("#people-batch button", "Remove selected") |> render_click()
      assert has_element?(view, "#confirm-remove", "Remove 3 people from Batch night?")
      view |> element("#confirm-remove button", "Remove") |> render_click()

      assert Agent.get(agent, & &1.deleted) == [41, 43]
      assert render(view) =~ "Removed 2 people."
      assert has_element?(view, "#remove-refused", "1 person could not be removed:")

      assert has_element?(
               view,
               "#remove-refused li",
               "Hugo Guest: Hugo Guest is seated in a room."
             )

      # the one who stayed stays checked
      assert has_element?(view, "#people-batch .count", "1 selected")
    end

    test "only the head's page has the batch: a member gets 403, an admin acts as head",
         %{conn: conn, member: member, club: club, session: session, signups: signups} do
      agent = stub_engine(signups)

      assert_error_sent 403, fn ->
        conn |> log_in(member) |> get(~p"/c/#{club.uuid}/owner/s/#{session.uuid}")
      end

      admin =
        user_fixture(%{node_user_id: 70})
        |> Ecto.Changeset.change(is_admin: true)
        |> Repo.update!()

      view = page(build_conn(), admin, club, session)
      view |> element(~s(#session-people input[phx-value-id="42"])) |> render_click()
      view |> element("#people-batch button", "Remove selected") |> render_click()
      view |> element("#confirm-remove button", "Remove") |> render_click()
      assert Agent.get(agent, & &1.deleted) == [42]
    end
  end

  describe "POST /api/cab/v1/sessions/:uuid/signups/remove" do
    test "the head removes several; the seated one is refused with the reason",
         %{conn: conn, head: head, session: session, signups: signups} do
      agent = stub_engine(signups, [seated(42)])

      body =
        conn
        |> log_in(head)
        |> post(~p"/api/cab/v1/sessions/#{session.uuid}/signups/remove", %{
          "participant_ids" => [41, 42, 43, 99]
        })
        |> json_response(200)

      assert body["removed"] == [41, 43]

      assert [
               %{"participant_id" => 42, "error" => seated},
               %{"participant_id" => 99, "error" => "That person isn't in this session."}
             ] = body["refused"]

      assert seated =~ "Hugo Guest is seated in a room"
      assert Agent.get(agent, & &1.deleted) == [41, 43]
    end

    test "all removed", %{conn: conn, head: head, session: session, signups: signups} do
      stub_engine(signups)

      assert %{"removed" => [41, 42, 43], "refused" => []} =
               conn
               |> log_in(head)
               |> post(~p"/api/cab/v1/sessions/#{session.uuid}/signups/remove", %{
                 "participant_ids" => [41, 42, 43]
               })
               |> json_response(200)
    end

    test "access like the single remove: 401, 403, 404",
         %{conn: conn, member: member, session: session, signups: signups} do
      agent = stub_engine(signups)
      body = %{"participant_ids" => [43]}
      path = ~p"/api/cab/v1/sessions/#{session.uuid}/signups/remove"

      assert conn |> post(path, body) |> json_response(401)
      # a member, even for their own signup: the batch is the head's
      assert conn |> log_in(member) |> post(path, body) |> json_response(403)

      outsider = user_fixture()
      assert conn |> log_in(outsider) |> post(path, body) |> json_response(403)

      assert conn
             |> log_in(member)
             |> post(~p"/api/cab/v1/sessions/#{Ecto.UUID.generate()}/signups/remove", body)
             |> json_response(404)

      assert Agent.get(agent, & &1.deleted) == []
    end

    test "a bad body is a 422", %{conn: conn, head: head, session: session, signups: signups} do
      agent = stub_engine(signups)
      path = ~p"/api/cab/v1/sessions/#{session.uuid}/signups/remove"
      conn = log_in(conn, head)

      for body <- [
            %{},
            %{"participant_ids" => []},
            %{"participant_ids" => "41"},
            %{"participant_ids" => [41, "42"]},
            %{"participant_ids" => [0]},
            %{"participant_ids" => Enum.to_list(1..201)}
          ] do
        assert %{"error" => "validation failed", "details" => %{"participant_ids" => _}} =
                 conn |> post(path, body) |> json_response(422),
               "expected 422 for #{inspect(body)}"
      end

      assert Agent.get(agent, & &1.deleted) == []
    end
  end

  describe "e-mailing a personal link" do
    test "an address the e-mail check refuses sends nothing",
         %{conn: conn, head: head, club: club, session: session, signups: signups} = ctx do
      stub_engine(signups)
      view = page(conn, head, club, session)

      for address <- ["a%00b@x.com", "a..b@x.com", "a@x"] do
        html =
          render_hook(view, "send_link", %{
            "link" => to_string(ctx.greta_link.id),
            "email" => address
          })

        assert html =~ "Enter an e-mail address like name@example.com."
      end

      Swoosh.TestAssertions.assert_no_email_sent()

      html =
        render_hook(view, "add_guest_by_email", %{
          "name" => "Ivy Invalid",
          "email" => "a%00b@x.com"
        })

      assert html =~ "Enter an e-mail address like name@example.com."
      refute Repo.get_by(User, name: "Ivy Invalid")
    end
  end
end
