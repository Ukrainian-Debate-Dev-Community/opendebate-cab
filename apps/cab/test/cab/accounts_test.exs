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
      info: struct(Ueberauth.Auth.Info, info),
      extra: %Ueberauth.Auth.Extra{raw_info: %{user: Map.get(overrides, :raw, %{})}}
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

    # the engine as a merge sees it: owner changes and the merge
    # itself, each call reported to the test; `merge` answers the merge
    defp stub_engine(merge \\ fn conn -> ok(conn, %{"moved" => 1}) end) do
      test_pid = self()

      Req.Test.stub(Core.Engine, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = if body == "", do: %{}, else: Jason.decode!(body)
        send(test_pid, {:engine, conn.method, conn.request_path, params})

        case {conn.method, conn.request_path} do
          {"POST", "/api/admins/merge"} -> merge.(conn)
          {"POST", "/api/organisations/" <> _} -> ok(conn, %{})
          {"DELETE", "/api/organisations/" <> _} -> ok(conn, %{})
        end
      end)
    end

    defp ok(conn, data), do: Req.Test.json(conn, %{"status" => "success", "data" => data})

    defp refuse(conn, status, message) do
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(status, Jason.encode!(%{"status" => "fail", "message" => message}))
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

      stub_engine()

      assert {:ok, merged} = Accounts.merge_accounts(target, source)
      assert merged.id == target.id

      assert_received {:engine, "POST", "/api/admins/merge",
                       %{"sourceUserId" => 502, "targetUserId" => 501}}

      assert Repo.get(Accounts.User, source.id) == nil
      assert [%{provider: "google"}] = Accounts.list_identities(target)

      roles =
        target
        |> Cab.Clubs.list_user_memberships()
        |> Map.new(&{&1.club_id, &1.status})

      # the approved membership beat the pending one; the other club came along
      assert roles == %{club.id => "approved", other_club.id => "approved"}
    end

    test "the account that heads a club is kept, whichever one is signed in" do
      head = user_fixture(%{node_user_id: 601})
      club = club_fixture(head, %{engine_organisation_id: 31})
      newcomer = user_fixture(%{node_user_id: 602})
      stub_engine()

      assert {:ok, kept} = Accounts.merge_accounts(newcomer, head)
      assert kept.id == head.id
      assert Accounts.kept_in_merge(newcomer, head).id == head.id

      assert_received {:engine, "POST", "/api/admins/merge",
                       %{"sourceUserId" => 602, "targetUserId" => 601}}

      assert Repo.get(Accounts.User, newcomer.id) == nil
      assert Cab.Clubs.role_for(club, kept) == :owner
    end

    test "with two heads the older account is kept and takes over the other's club" do
      older = user_fixture(%{node_user_id: 701})
      younger = user_fixture(%{node_user_id: 702})
      _own = club_fixture(older, %{engine_organisation_id: 41})
      theirs = club_fixture(younger, %{engine_organisation_id: 42})
      stub_engine()

      assert {:ok, kept} = Accounts.merge_accounts(younger, older)
      assert kept.id == older.id

      # the engine owner moves before the merge, which it would refuse otherwise
      assert_received {:engine, "POST", "/api/organisations/42/owners", %{"targetUserId" => 701}}

      assert_received {:engine, "DELETE", "/api/organisations/42/owners/702", _}
      assert_received {:engine, "POST", "/api/admins/merge", %{"sourceUserId" => 702}}

      assert Cab.Clubs.role_for(theirs, kept) == :owner
      assert Cab.Clubs.head_of(theirs).id == older.id
    end

    test "a refused merge hands the clubs back; nothing changes" do
      older = user_fixture(%{node_user_id: 801})
      younger = user_fixture(%{node_user_id: 802})
      club = club_fixture(younger, %{engine_organisation_id: 51})

      stub_engine(&refuse(&1, 409, "Both users are registered in event 11; remove one first."))

      # the head is kept, so the older non-head account is the one folded
      assert {:error, "Both accounts took part in the same session" <> _} =
               Accounts.merge_accounts(older, younger)

      refute_received {:engine, "POST", "/api/organisations/51/owners", _}
      assert Repo.get(Accounts.User, older.id)
      assert Cab.Clubs.head_of(club).id == younger.id

      # with a club of its own the older account is the one kept, so
      # the younger one's club is handed over and, the merge being
      # refused, handed back
      _own = club_fixture(older, %{engine_organisation_id: 52})

      assert {:error, _} = Accounts.merge_accounts(older, younger)
      assert_received {:engine, "POST", "/api/organisations/51/owners", %{"targetUserId" => 801}}
      assert_received {:engine, "DELETE", "/api/organisations/51/owners/802", _}
      assert_received {:engine, "POST", "/api/organisations/51/owners", %{"targetUserId" => 802}}
      assert_received {:engine, "DELETE", "/api/organisations/51/owners/801", _}
      assert Cab.Clubs.head_of(club).id == younger.id
      assert Repo.get(Accounts.User, younger.id)
    end

    test "a merge the engine already finished completes on a second run" do
      target = user_fixture(%{node_user_id: 901})
      source = user_fixture(%{node_user_id: 902})
      stub_engine(&refuse(&1, 404, "Source user not found."))

      assert {:ok, kept} = Accounts.merge_accounts(target, source)
      assert kept.id == target.id
      assert Repo.get(Accounts.User, source.id) == nil
    end
  end

  describe "a new sign-in with a known address" do
    import Cab.Fixtures

    test "Google's verified address finds the account instead of making a second one" do
      {:ok, user} = Accounts.upsert_from_oauth(auth(%{info: %{email: "Ola@Example.com"}}))

      google =
        auth(%{
          provider: :google,
          uid: 5,
          info: %{email: "ola@example.com"},
          raw: %{"email_verified" => true}
        })

      assert {:existing, found, pending} = Accounts.upsert_from_oauth(google)
      assert found.id == user.id
      assert %{provider: "google", uid: "5"} = pending
      assert Repo.aggregate(Accounts.User, :count) == 1

      # chosen on /signin: a separate account after all
      assert {:ok, separate} = Accounts.create_pending(pending)
      refute separate.id == user.id
    end

    test "GitHub counts an address it flags as verified, or the profile's public one" do
      _user = user_fixture(%{email: "gh@example.com"})

      flagged =
        auth(%{
          uid: 6,
          info: %{email: "gh@example.com"},
          raw: %{"emails" => [%{"email" => "gh@example.com", "verified" => true}]}
        })

      assert {:existing, _, _} = Accounts.upsert_from_oauth(flagged)

      public =
        auth(%{uid: 7, info: %{email: "gh@example.com"}, raw: %{"email" => "gh@example.com"}})

      assert {:existing, _, _} = Accounts.upsert_from_oauth(public)
    end

    test "an address the provider does not vouch for makes a separate account" do
      user = user_fixture(%{email: "same@example.com"})

      unverified =
        auth(%{
          uid: 8,
          info: %{email: "same@example.com"},
          raw: %{"emails" => [%{"email" => "same@example.com", "verified" => false}]}
        })

      assert {:ok, other} = Accounts.upsert_from_oauth(unverified)
      refute other.id == user.id

      google = auth(%{provider: :google, uid: 9, info: %{email: "same@example.com"}})
      assert {:ok, _} = Accounts.upsert_from_oauth(google)
    end

    test "the pending sign-in is added by linking it to the found account" do
      {:ok, user} = Accounts.upsert_from_oauth(auth(%{info: %{email: "pat@example.com"}}))

      google =
        auth(%{
          provider: :google,
          uid: 10,
          info: %{email: "pat@example.com"},
          raw: %{"email_verified" => true}
        })

      {:existing, _, pending} = Accounts.upsert_from_oauth(google)
      assert {:ok, :linked} = Accounts.link_identity(user, pending)
      assert {:ok, again} = Accounts.upsert_from_oauth(google)
      assert again.id == user.id
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
