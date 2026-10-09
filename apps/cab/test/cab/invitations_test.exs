defmodule Cab.InvitationsTest do
  use CabWeb.ConnCase, async: false

  import Cab.Fixtures
  import Phoenix.LiveViewTest

  alias Cab.Invitations
  alias Cab.Invitations.Invitation
  alias Cab.Repo

  setup do
    Req.Test.set_req_test_to_shared()
    on_exit(fn -> Req.Test.set_req_test_to_private() end)

    head = user_fixture(%{node_user_id: 9, username: "head"})
    club = club_fixture(head, %{engine_organisation_id: 3})
    session = session_fixture(club, engine_event_id: 11)
    {:ok, agent} = Agent.start_link(fn -> %{signups: [], rooms: [], calls: []} end)
    stub(agent)
    %{head: head, club: club, session: session, agent: agent}
  end

  defp ok(conn, data), do: Req.Test.json(conn, %{"status" => "success", "data" => data})

  # an engine kept in an Agent: participants appear as cab adds them
  defp stub(agent) do
    Req.Test.stub(Core.Engine, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      params = if body == "", do: %{}, else: Jason.decode!(body)
      Agent.update(agent, &%{&1 | calls: &1.calls ++ [{conn.method, conn.request_path, params}]})

      case {conn.method, conn.request_path} do
        {"GET", "/api/events/11"} ->
          ok(conn, %{"id" => 11, "name" => "Open night", "status" => "scheduled"})

        {"GET", "/api/events/11/rounds"} ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        {"GET", "/api/events/11/participants"} ->
          ok(conn, Agent.get(agent, & &1.signups))

        {"GET", "/api/rounds/21/rooms"} ->
          ok(conn, Agent.get(agent, & &1.rooms))

        {"POST", "/api/events/11/participants"} ->
          id = 40 + length(Agent.get(agent, & &1.signups))

          row = %{
            "id" => id,
            "user_id" => params["user_id"],
            "display_name" => params["display_name"],
            "role" => params["role"]
          }

          Agent.update(agent, &%{&1 | signups: &1.signups ++ [row]})

          if params["user_id"],
            do: ok(conn, row),
            else: ok(conn, Map.put(row, "raw_claim_token", "token-#{id}"))

        {"POST", "/api/users/register"} ->
          Req.Test.json(conn, %{"token" => Core.Engine.mint_token(900)})

        {"POST", "/api/users/claim-participant/" <> _pid} ->
          ok(conn, %{})

        {"GET", "/api/users/schedule"} ->
          ok(conn, %{"as_adjudicator" => [], "as_player" => []})

        {"GET", "/api/users/history"} ->
          ok(conn, %{"as_adjudicator" => [], "as_player" => []})

        {"GET", "/api/users/" <> _stats} ->
          ok(conn, nil)

        {"PUT", "/api/events/11/participants/" <> _pid} ->
          ok(conn, %{})

        {"DELETE", "/api/events/11/participants/" <> pid} ->
          pid = String.to_integer(pid)

          Agent.update(
            agent,
            &%{&1 | signups: Enum.reject(&1.signups, fn p -> p["id"] == pid end)}
          )

          Req.Test.json(conn, %{"status" => "success"})
      end
    end)
  end

  defp calls(agent, method, prefix) do
    for {^method, path, params} <- Agent.get(agent, & &1.calls),
        String.starts_with?(path, prefix),
        do: {path, params}
  end

  describe "search" do
    test "members by prefix, others only by exact username or email, guests never",
         %{club: club, session: session} do
      anna = user_fixture(%{username: "anna", name: "Anna Kovalenko"})
      membership_fixture(anna, club)
      _andriy = user_fixture(%{username: "andriy-k", email: "andriy@example.com"})
      guest = user_fixture(%{username: "guest-anon", name: "Andrii"})
      link_fixture(guest, session)

      hits = Invitations.search(club, session, [], "an")
      assert Enum.map(hits.members, & &1.username) == ["anna"]
      assert hits.users == []
      # a member answers to it, so it is not offered as a guest
      assert hits.guest == nil
      assert Invitations.search(club, session, [], "Zara").guest == "Zara"

      # surnames match too
      assert [%{username: "anna"}] = Invitations.search(club, session, [], "kov").members

      # a non-member appears only on an exact username or email
      assert [%{username: "andriy-k"}] = Invitations.search(club, session, [], "ANDRIY-K").users
      email = Invitations.search(club, session, [], "andriy@example.com")
      assert [%{username: "andriy-k"}] = email.users
      assert email.guest == nil

      # a personal-link guest is never offered, even by exact name
      assert Invitations.search(club, session, [], "guest-anon").users == []
    end

    test "with nothing typed, every member not in the session is listed by name",
         %{club: club, session: session, head: head} do
      zoe = user_fixture(%{username: "zoe", name: "Zoe Moroz", node_user_id: 511})
      bo = user_fixture(%{username: "bo", name: "Bohdan Lys", node_user_id: 512})
      membership_fixture(zoe, club)
      membership_fixture(bo, club)
      _outsider = user_fixture(%{username: "outsider"})

      everyone = Invitations.search(club, session, [], "").members
      assert Enum.map(everyone, & &1.id) |> Enum.sort() == Enum.sort([head.id, zoe.id, bo.id])

      assert Enum.find_index(everyone, &(&1.id == bo.id)) <
               Enum.find_index(everyone, &(&1.id == zoe.id))

      signups = [%{"id" => 41, "user_id" => 511, "display_name" => "zoe"}]

      refute Enum.any?(
               Invitations.search(club, session, signups, "  ").members,
               &(&1.id == zoe.id)
             )
    end

    test "people already in the session are not offered again",
         %{club: club, session: session, head: head} do
      anna = user_fixture(%{username: "anna", node_user_id: 501})
      membership_fixture(anna, club)
      signups = [%{"id" => 41, "user_id" => 501, "display_name" => "anna"}]

      assert Invitations.search(club, session, signups, "ann").members == []

      bohdan = user_fixture(%{username: "bohdan"})
      {:ok, _} = Invitations.invite(head, session, bohdan)
      assert Invitations.search(club, session, [], "bohdan").users == []
    end
  end

  describe "invite, accept, decline" do
    test "the head seats an invited user at once; accepting claims the place",
         %{head: head, session: session, agent: agent} do
      olena = user_fixture(%{username: "olena", name: "Olena P", node_user_id: 600})

      {:ok, invitation} = Invitations.invite(head, session, olena)
      assert invitation.claim_token == "token-40"

      # the engine row carries her name and no user
      assert [{_, %{"display_name" => "Olena P"} = added}] =
               calls(agent, "POST", "/api/events/11/participants")

      refute Map.has_key?(added, "user_id")

      assert {:error, "olena" <> _} = Invitations.invite(head, session, olena) |> name_error()

      assert [mine] = Invitations.for_user(olena)
      assert {:ok, :accepted} = Invitations.accept(mine, olena)

      assert [{"/api/users/claim-participant/40", %{"claim_token" => "token-40"}}] =
               calls(agent, "POST", "/api/users/claim-participant")

      assert Invitations.for_user(olena) == []
    end

    test "declining gives up a waitlist place and removes the name",
         %{head: head, session: session, agent: agent} do
      olena = user_fixture(%{username: "olena", node_user_id: 600})
      {:ok, invitation} = Invitations.invite(head, session, olena)

      assert :ok = Invitations.decline(Repo.preload(invitation, session: :club))

      assert [{"/api/events/11/participants/40", %{"display_name" => "removed"}}] =
               calls(agent, "PUT", "/api/events/11/participants")

      assert [{"/api/events/11/participants/40", _}] =
               calls(agent, "DELETE", "/api/events/11/participants")

      assert Repo.all(Invitation) == []
    end

    test "removing the invited person's place also drops the invitation",
         %{head: head, session: session} do
      olena = user_fixture(%{username: "olena", node_user_id: 600})
      {:ok, _invitation} = Invitations.invite(head, session, olena)

      assert :ok = Cab.Sessions.remove_signup(head, session, 40)
      assert Repo.all(Invitation) == []
    end

    test "registering through the shared link accepts a pending invitation",
         %{conn: conn, head: head, session: session, agent: agent} do
      olena = user_fixture(%{username: "olena", node_user_id: 600})
      {:ok, _invitation} = Invitations.invite(head, session, olena)

      conn
      |> init_test_session(%{user_id: olena.id})
      |> Plug.Conn.put_private(:plug_skip_csrf_protection, true)
      |> post(~p"/r/#{session.uuid}")

      assert [_claim] = calls(agent, "POST", "/api/users/claim-participant")
      # no second registration in the engine
      assert length(calls(agent, "POST", "/api/events/11/participants")) == 1
    end

    test "home points at My page, which lists the invitation with accept and decline",
         %{conn: conn, head: head, session: session} do
      olena = user_fixture(%{username: "olena", node_user_id: 600})
      {:ok, invitation} = Invitations.invite(head, session, olena)

      home = conn |> init_test_session(%{user_id: olena.id}) |> get(~p"/") |> html_response(200)
      assert home =~ "A club head added you to a session."

      html = conn |> init_test_session(%{user_id: olena.id}) |> get(~p"/me") |> html_response(200)
      assert html =~ ~s(id="my-invitations")
      assert html =~ "/invitations/#{invitation.id}/accept"
      assert html =~ "/invitations/#{invitation.id}/decline"

      # someone else's invitation is a 404
      other = user_fixture(%{username: "other"})

      assert conn
             |> init_test_session(%{user_id: other.id})
             |> Plug.Conn.put_private(:plug_skip_csrf_protection, true)
             |> post(~p"/invitations/#{invitation.id}/accept")
             |> response(404)
    end
  end

  test "the owner page: type, pick, and the person is in", %{
    conn: conn,
    head: head,
    club: club,
    session: session,
    agent: agent
  } do
    anna = user_fixture(%{username: "anna", node_user_id: 501})
    membership_fixture(anna, club)
    user_fixture(%{username: "olena", email: "olena@example.com", node_user_id: 600})

    {:ok, view, _html} =
      conn
      |> init_test_session(%{user_id: head.id})
      |> live(~p"/c/#{club.uuid}/owner/s/#{session.uuid}")

    html = view |> form("#add-person-form", %{q: "an"}) |> render_change()
    assert html =~ "<span>member</span>"
    # a member answers to it, so no guest is offered
    refute html =~ "as a guest"

    view |> element("#add-person-suggestions button", "anna") |> render_click()
    assert [{_, %{"user_id" => 501}}] = calls(agent, "POST", "/api/events/11/participants")

    html = view |> form("#add-person-form", %{q: "olena@example.com"}) |> render_change()
    assert html =~ "registered user, will accept"
    view |> element("#add-person-suggestions button", "olena") |> render_click()
    assert [%Invitation{}] = Repo.all(Invitation)
    assert render(view) =~ "invited, not accepted yet"

    # a name nobody in cab answers to: a guest, with what to do next
    html = view |> form("#add-person-form", %{q: "Zara Nova"}) |> render_change()
    assert html =~ "Add “Zara Nova” as a guest"
    assert html =~ "copy it from People below"

    # an address nobody uses: a name field, the address never stored
    html = view |> form("#add-person-form", %{q: "nova@example.com"}) |> render_change()
    assert html =~ ~s(id="add-guest-by-email")
    refute html =~ "as a guest <span>"

    html =
      view
      |> form("#add-guest-by-email", %{name: "Zara Nova"})
      |> render_submit()

    assert html =~ "Zara Nova added as a guest"
    assert html =~ "send it to nova@example.com"

    assert Enum.any?(
             calls(agent, "POST", "/api/events/11/participants"),
             fn {_, params} -> params["display_name"] == "Zara Nova" end
           )

    refute Repo.get_by(Cab.Accounts.User, email: "nova@example.com")
  end

  defp name_error({:error, message}), do: {:error, String.downcase(message)}
  defp name_error(other), do: other
end
