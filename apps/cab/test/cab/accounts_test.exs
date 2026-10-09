defmodule Cab.AccountsTest do
  use Cab.DataCase, async: true

  alias Cab.Accounts

  defp auth(overrides \\ %{}) do
    info =
      Map.merge(
        %{nickname: "debater", name: "Debate Person", email: "d@example.com", image: nil},
        Map.get(overrides, :info, %{})
      )

    %Ueberauth.Auth{
      provider: Map.get(overrides, :provider, :github),
      uid: Map.get(overrides, :uid, 12_345),
      info: struct(Ueberauth.Auth.Info, info)
    }
  end

  test "first oauth login creates user and identity" do
    assert {:ok, user} = Accounts.upsert_from_oauth(auth())
    assert user.username == "debater"
    assert user.email == "d@example.com"
    assert [identity] = Repo.preload(user, :identities).identities
    assert identity.provider == "github"
    assert identity.provider_uid == "12345"
  end

  test "second login with same identity reuses the user and refreshes profile" do
    {:ok, first} = Accounts.upsert_from_oauth(auth())

    {:ok, second} =
      Accounts.upsert_from_oauth(auth(%{info: %{name: "Renamed", email: "new@example.com"}}))

    assert second.id == first.id
    assert second.name == "Renamed"
    assert second.email == "new@example.com"
    assert Repo.aggregate(Accounts.User, :count) == 1
  end

  test "username collision from another provider gets a suffix" do
    {:ok, _github} = Accounts.upsert_from_oauth(auth())
    {:ok, google} = Accounts.upsert_from_oauth(auth(%{provider: :google, uid: 999}))

    assert google.username != "debater"
    assert String.starts_with?(google.username, "debater-")
  end

  test "a Google sign-in is named after the person, never the e-mail address" do
    {:ok, user} =
      Accounts.upsert_from_oauth(
        auth(%{
          provider: :google,
          uid: 42,
          info: %{nickname: nil, name: "Olena Petrenko", email: "olena@gmail.com"}
        })
      )

    assert user.username == "olena-petrenko"
    refute user.username =~ "@"
  end

  describe "linking and merging" do
    import Cab.Fixtures

    defp stub_merge(fun) do
      Req.Test.stub(Core.Engine, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        fun.(conn, Jason.decode!(body))
      end)
    end

    test "link a second method, see it already linked, refuse a second of the same kind, unlink" do
      {:ok, user} = Accounts.upsert_from_oauth(auth())

      assert {:ok, :linked} = Accounts.link_identity(user, auth(%{provider: :google, uid: 7}))
      assert {:ok, :already} = Accounts.link_identity(user, auth(%{provider: :google, uid: 7}))
      assert {:error, _} = Accounts.link_identity(user, auth(%{provider: :google, uid: 8}))

      assert {:ok, _} = Accounts.unlink_identity(user, "google")

      assert {:error, "Keep at least one way to sign in."} =
               Accounts.unlink_identity(user, "github")
    end

    test "a sign-in that has its own account is offered for merging" do
      {:ok, user} = Accounts.upsert_from_oauth(auth())
      {:ok, other} = Accounts.upsert_from_oauth(auth(%{provider: :google, uid: 9}))

      assert {:other_account, found} =
               Accounts.link_identity(user, auth(%{provider: :google, uid: 9}))

      assert found.id == other.id
    end

    test "merging moves history, sign-ins and the stronger membership, then closes the other account" do
      head = user_fixture(%{node_user_id: 9})
      club = club_fixture(head)
      other_club = club_fixture(user_fixture(%{node_user_id: 10}))

      target = user_fixture(%{node_user_id: 501})
      source = user_fixture(%{node_user_id: 502})
      membership_fixture(target, club, status: "pending")
      membership_fixture(source, club)
      membership_fixture(source, other_club)

      %Accounts.Identity{user_id: source.id}
      |> Accounts.Identity.changeset(%{provider: "google", provider_uid: "77"})
      |> Repo.insert!()

      test_pid = self()

      stub_merge(fn conn, params ->
        send(test_pid, {:merge, params})
        Req.Test.json(conn, %{"status" => "success", "data" => %{"moved" => 3}})
      end)

      assert {:ok, merged} = Accounts.merge_accounts(target, source)
      assert merged.id == target.id
      assert_received {:merge, %{"sourceUserId" => 502, "targetUserId" => 501}}

      assert Repo.get(Accounts.User, source.id) == nil
      assert [%{provider: "google"}] = Accounts.list_identities(target)

      roles =
        target
        |> Cab.Clubs.list_user_memberships()
        |> Map.new(&{&1.club_id, &1.status})

      # the approved membership beat the pending one; the other club came along
      assert roles == %{club.id => "approved", other_club.id => "approved"}
    end

    test "the merge is refused when the other account heads a club; nothing changes" do
      target = user_fixture(%{node_user_id: 501})
      source = user_fixture(%{node_user_id: 502})

      stub_merge(fn conn, _params ->
        conn
        |> Plug.Conn.put_resp_content_type("application/json")
        |> Plug.Conn.send_resp(
          409,
          ~s({"status":"fail","message":"The source user holds roles beyond participations and cannot be merged."})
        )
      end)

      assert {:error, "That account heads a club" <> _} = Accounts.merge_accounts(target, source)
      assert Repo.get(Accounts.User, source.id)
    end
  end

  describe "ensure_node_user/1" do
    defp engine_token(claims) do
      Joken.generate_and_sign!(%{}, claims, Joken.Signer.create("HS256", "test-engine-secret"))
    end

    test "provisions an engine user and persists node_user_id" do
      {:ok, user} = Accounts.upsert_from_oauth(auth())
      assert user.node_user_id == nil

      Req.Test.stub(Core.Engine, fn conn ->
        Req.Test.json(conn, %{"status" => "ok", "token" => engine_token(%{"id" => 42})})
      end)

      updated = Accounts.ensure_node_user(user)
      assert updated.node_user_id == 42
      assert Accounts.get_user(user.id).node_user_id == 42
    end

    test "is a no-op when the user is already provisioned" do
      {:ok, user} = Accounts.upsert_from_oauth(auth())
      {:ok, user} = Accounts.set_node_user_id(user, 7)

      # No Req.Test stub: any HTTP call here would raise.
      assert Accounts.ensure_node_user(user).node_user_id == 7
    end

    test "continues without node_user_id when the engine is down" do
      {:ok, user} = Accounts.upsert_from_oauth(auth())

      Req.Test.stub(Core.Engine, fn conn ->
        Req.Test.transport_error(conn, :econnrefused)
      end)

      log =
        ExUnit.CaptureLog.capture_log(fn ->
          assert Accounts.ensure_node_user(user).node_user_id == nil
        end)

      assert log =~ "engine provisioning failed"
    end
  end
end
