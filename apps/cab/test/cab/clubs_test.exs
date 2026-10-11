defmodule Cab.ClubsTest do
  use Cab.DataCase, async: true

  import Cab.Fixtures

  alias Cab.Clubs

  defp stub(fun) do
    Req.Test.stub(Core.Engine, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      params = if body == "", do: %{}, else: Jason.decode!(body)
      fun.(conn, params)
    end)
  end

  defp ok(conn, data), do: Req.Test.json(conn, %{"status" => "success", "data" => data})

  defp join_answers, do: %{"message" => "about me", "contact" => "@tg"}

  defp claims(conn) do
    ["Bearer " <> token] = Plug.Conn.get_req_header(conn, "authorization")
    signer = Joken.Signer.create("HS256", "test-engine-secret")
    {:ok, claims} = Joken.verify(token, signer)
    claims
  end

  describe "create_club/3" do
    test "creates the engine org (admin token, head as owner) + rows" do
      head = user_fixture(%{node_user_id: 9})

      stub(fn conn, params ->
        assert conn.method == "POST"
        assert conn.request_path == "/api/organisations"
        assert params == %{"name" => "Kyiv Debate", "owner_id" => 9}
        assert %{"id" => 9, "isAdmin" => true} = claims(conn)
        ok(conn, %{"id" => 3, "name" => "Kyiv Debate"})
      end)

      assert {:ok, club} = Clubs.create_club("Kyiv Debate", "Kyiv", head)
      assert club.engine_organisation_id == 3
      assert club.city == "Kyiv"
      assert {:ok, _} = Ecto.UUID.cast(club.uuid)

      assert Clubs.role_for(club, head) == :owner
      assert [%{role: "head"}] = Clubs.list_members(club)
    end

    test "the role ladder: admin covers every tree, each step covers the ones below" do
      head = user_fixture()
      club = club_fixture(head)

      admin = user_fixture() |> Ecto.Changeset.change(is_admin: true) |> Cab.Repo.update!()
      assert Clubs.role_for(club, admin) == :admin

      for role <- [:public, :member, :owner, :admin], do: assert(Clubs.covers?(:admin, role))
      for role <- [:public, :member, :owner], do: assert(Clubs.covers?(:owner, role))
      for role <- [:public, :member], do: assert(Clubs.covers?(:member, role))
      assert Clubs.covers?(:public, :public)

      refute Clubs.covers?(:owner, :admin)
      refute Clubs.covers?(:member, :owner)
      refute Clubs.covers?(:public, :member)
    end

    test "engine failure creates no rows" do
      head = user_fixture()

      stub(fn conn, _params ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(403, ~s({"status":"fail","message":"nope"}))
      end)

      assert {:error, "nope"} = Clubs.create_club("X", nil, head)
      assert Repo.aggregate(Cab.Clubs.Club, :count) == 0
    end
  end

  describe "join requests" do
    setup do
      head = user_fixture()
      club = club_fixture(head)
      %{head: head, club: club}
    end

    test "request_join is a pending membership carrying the form's answers", %{club: club} do
      user = user_fixture()
      assert Clubs.role_for(club, user) == :public

      assert {:ok, membership} =
               Clubs.request_join(user, club, %{
                 "message" => "I debated at school",
                 "contact" => "@anna_tg"
               })

      assert membership.status == "pending"
      assert membership.message == "I debated at school"
      assert membership.contact == "@anna_tg"
      # pending = still public
      assert Clubs.role_for(club, user) == :public
      assert [request] = Clubs.list_join_requests(club)
      assert request.id == membership.id

      assert {:ok, approved} = Clubs.approve_join(Clubs.get_membership(membership.id))
      assert approved.status == "approved"
      assert Clubs.role_for(club, user) == :member
      assert Clubs.list_join_requests(club) == []
    end

    test "both answers are REQUIRED - never a bare button", %{club: club} do
      user = user_fixture()

      assert {:error, changeset} = Clubs.request_join(user, club)
      assert %{message: [_], contact: [_]} = errors_on(changeset)

      assert {:error, changeset} = Clubs.request_join(user, club, %{"message" => "hi"})
      assert %{contact: [_]} = errors_on(changeset)
    end

    test "decline deletes the pending membership", %{club: club} do
      user = user_fixture()
      {:ok, membership} = Clubs.request_join(user, club, join_answers())

      assert {:ok, _} = Clubs.decline_join(Clubs.get_membership(membership.id))
      assert Clubs.get_membership(membership.id) == nil
      assert Clubs.role_for(club, user) == :public
    end

    test "a second request is rejected", %{club: club} do
      user = user_fixture()
      {:ok, _} = Clubs.request_join(user, club, join_answers())
      assert {:error, changeset} = Clubs.request_join(user, club, join_answers())
      assert %{user_id: [_]} = errors_on(changeset)
    end

    test "approve/decline refuse non-pending memberships", %{club: club, head: head} do
      membership = Clubs.get_membership(hd(Clubs.list_members(club)).id)
      assert membership.user_id == head.id
      assert {:error, _} = Clubs.approve_join(membership)
      assert {:error, _} = Clubs.decline_join(membership)
    end
  end

  describe "club_history/1" do
    test "finished sessions with their recorded winners - no engine call" do
      head = user_fixture(%{node_user_id: 9})
      club = club_fixture(head, %{engine_organisation_id: 3})

      done =
        session_fixture(club,
          engine_event_id: 11,
          name: "Done night",
          finished_at: ~U[2026-10-08 20:00:00Z],
          winner_name: "Winners"
        )

      _open = session_fixture(club, engine_event_id: 12)

      stub(fn _conn, _params -> raise "club_history must not call the engine" end)

      assert {:ok, [row]} = Clubs.club_history(club)
      assert {row.session_uuid, row.name, row.winner} == {done.uuid, "Done night", "Winners"}
    end
  end

  describe "update_club/2" do
    test "edits name and city; the name stays required" do
      head = user_fixture()
      club = club_fixture(head, %{name: "Old Name", city: "Kyiv"})

      Req.Test.stub(Core.Engine, fn conn ->
        Req.Test.json(conn, %{"status" => "success", "data" => %{}})
      end)

      assert {:ok, updated} = Clubs.update_club(club, %{"name" => "New Name", "city" => "Lviv"})
      assert updated.name == "New Name"
      assert updated.city == "Lviv"
      assert updated.uuid == club.uuid

      assert {:error, changeset} = Clubs.update_club(club, %{"name" => ""})
      assert %{name: ["can't be blank"]} = errors_on(changeset)
    end
  end

  describe "remove_member/2" do
    test "removes a member row; never the head; 'no such member' otherwise" do
      head = user_fixture()
      club = club_fixture(head)
      member = user_fixture()
      membership_fixture(member, club)

      assert {:ok, _} = Clubs.remove_member(club, member.id)
      assert Clubs.role_for(club, member) == :public

      assert {:error, "The club head cannot be removed."} = Clubs.remove_member(club, head.id)
      assert Clubs.role_for(club, head) == :owner

      assert {:error, "That person is not a member of this club."} =
               Clubs.remove_member(club, member.id)

      # a pending request can be removed too (same as declining)
      pending = user_fixture()
      {:ok, _} = Clubs.request_join(pending, club, join_answers())
      assert {:ok, _} = Clubs.remove_member(club, pending.id)
      assert Clubs.list_join_requests(club) == []
    end
  end

  describe "archive_club/1" do
    test "archived clubs leave the public directory but keep their rows" do
      head = user_fixture()
      club = club_fixture(head)
      live = club_fixture(user_fixture())

      assert {:ok, archived} = Clubs.archive_club(club)
      assert archived.archived_at != nil

      listed = Clubs.list_clubs() |> Enum.map(& &1.id)
      assert live.id in listed
      refute club.id in listed

      # the admin listing still sees it
      assert club.id in (Clubs.list_all_clubs() |> Enum.map(& &1.id))
    end
  end

  describe "update_club/2 and the engine organisation" do
    test "a rename reaches the engine organisation first; other edits stay in cab" do
      head = user_fixture(%{node_user_id: 9})
      club = club_fixture(head, %{engine_organisation_id: 3, name: "Old Name"})
      test_pid = self()

      stub(fn conn, params ->
        send(test_pid, {conn.method, conn.request_path, params})
        ok(conn, %{"id" => 3, "name" => params["name"]})
      end)

      assert {:ok, %{city: "Lviv"}} = Clubs.update_club(club, %{"city" => "Lviv"})
      refute_received {_, _, _}

      assert {:ok, %{name: "New Name"}} = Clubs.update_club(club, %{"name" => "New Name"})
      assert_received {"PUT", "/api/organisations/3", %{"name" => "New Name"}}
    end

    test "an engine refusal keeps the old name in cab too" do
      head = user_fixture(%{node_user_id: 9})
      club = club_fixture(head, %{engine_organisation_id: 3, name: "Kept Name"})

      stub(fn conn, _params ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(403, ~s({"status":"fail","message":"nope"}))
      end)

      assert {:error, _} = Clubs.update_club(club, %{"name" => "Other Name"})
      assert Repo.get!(Cab.Clubs.Club, club.id).name == "Kept Name"
    end
  end

  describe "change_head/2" do
    test "the engine org's owner changes too; memberships swap roles" do
      old_head = user_fixture(%{node_user_id: 9})
      new_head = user_fixture(%{node_user_id: 10})
      club = club_fixture(old_head, %{engine_organisation_id: 3})
      test_pid = self()

      stub(fn conn, params ->
        send(test_pid, {conn.method, conn.request_path, params})
        ok(conn, %{"id" => 1})
      end)

      assert {:ok, _club} = Clubs.change_head(club, new_head)
      assert_received {"POST", "/api/organisations/3/owners", %{"targetUserId" => 10}}
      # the old head stops owning it, so that account can be merged later
      assert_received {"DELETE", "/api/organisations/3/owners/9", _}
      assert Clubs.role_for(club, new_head) == :owner
      assert Clubs.role_for(club, old_head) == :member
      assert Clubs.head_of(club).id == new_head.id
    end

    test "an engine refusal changes nothing" do
      old_head = user_fixture(%{node_user_id: 9})
      new_head = user_fixture(%{node_user_id: 10})
      club = club_fixture(old_head, %{engine_organisation_id: 3})

      stub(fn conn, _params ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(403, ~s({"status":"fail","message":"nope"}))
      end)

      assert {:error, "nope"} = Clubs.change_head(club, new_head)
      assert Clubs.role_for(club, old_head) == :owner
    end
  end
end
