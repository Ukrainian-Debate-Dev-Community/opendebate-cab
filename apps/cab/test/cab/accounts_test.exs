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
