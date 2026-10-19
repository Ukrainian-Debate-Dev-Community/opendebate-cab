defmodule CabWeb.AccountMergeTest do
  use CabWeb.ConnCase, async: true

  import Cab.Fixtures
  import Ecto.Query, only: [from: 2]

  alias Cab.Accounts

  defp signed_in(conn, user, extra \\ %{}) do
    conn
    |> init_test_session(Map.merge(%{user_id: user.id}, extra))
    |> Plug.Conn.put_private(:plug_skip_csrf_protection, true)
  end

  test "the Account page offers to link whichever method is missing", %{conn: conn} do
    user = user_fixture()

    %Accounts.Identity{user_id: user.id}
    |> Accounts.Identity.changeset(%{provider: "github", provider_uid: "1"})
    |> Cab.Repo.insert!()

    html = conn |> signed_in(user) |> get(~p"/account") |> html_response(200)
    assert html =~ ~s(href="/account/link/google")
    assert html =~ "your only sign-in"
    # one gold action: Save in the chrome; the claim form's button is plain
    refute html =~ ~s(class="btn-go")

    linking = conn |> signed_in(user) |> get(~p"/account/link/google")
    assert redirected_to(linking) == "/auth/google"
    assert get_session(linking, :link_to) == user.id
  end

  test "a merge is offered only for the account just proven, and can be declined",
       %{conn: conn} do
    user = user_fixture()
    other = user_fixture(%{username: "second-me"})

    # without a candidate from a link, there is nothing to merge
    assert conn |> signed_in(user) |> get(~p"/account/merge") |> redirected_to() == "/account"

    page = conn |> signed_in(user, %{merge_candidate: other.id}) |> get(~p"/account/merge")
    assert html_response(page, 200) =~ "second-me"

    kept =
      conn
      |> signed_in(user, %{merge_candidate: other.id})
      |> post(~p"/account/merge", %{decision: "keep"})

    assert redirected_to(kept) == "/account"
    assert Cab.Repo.get(Accounts.User, other.id)
  end

  test "merging from the newer account keeps the head's and signs in to it", %{conn: conn} do
    head = user_fixture(%{node_user_id: 611, username: "the-head"})
    club = club_fixture(head, %{engine_organisation_id: 61})
    newcomer = user_fixture(%{node_user_id: 612})

    Req.Test.stub(Core.Engine, fn conn ->
      Req.Test.json(conn, %{"status" => "success", "data" => %{"moved" => 0}})
    end)

    page = conn |> signed_in(newcomer, %{merge_candidate: head.id}) |> get(~p"/account/merge")
    assert html_response(page, 200) =~ "The merged account is <b>the-head</b>"

    merged =
      conn
      |> signed_in(newcomer, %{merge_candidate: head.id})
      |> post(~p"/account/merge", %{decision: "merge"})

    assert redirected_to(merged) == "/account"
    assert get_session(merged, :user_id) == head.id
    assert Phoenix.Flash.get(merged.assigns.flash, :info) =~ "merged into the-head"
    assert Cab.Repo.get(Accounts.User, newcomer.id) == nil
    assert Cab.Clubs.head_of(club).id == head.id
  end

  describe "a new sign-in whose verified address has an account" do
    defp google(uid, email) do
      %Ueberauth.Auth{
        provider: :google,
        uid: uid,
        info: %Ueberauth.Auth.Info{name: "Ola", email: email},
        extra: %Ueberauth.Auth.Extra{raw_info: %{user: %{"email_verified" => true}}}
      }
    end

    defp github(uid) do
      %Ueberauth.Auth{
        provider: :github,
        uid: uid,
        info: %Ueberauth.Auth.Info{nickname: "ola", email: "ola@example.com"}
      }
    end

    # the provider hop already done: the callback with its result
    defp callback(session, auth) do
      build_conn()
      |> init_test_session(session)
      |> Phoenix.Controller.fetch_flash()
      |> Plug.Conn.assign(:ueberauth_auth, auth)
      |> CabWeb.AuthController.callback(%{})
    end

    defp carrying(asked) do
      build_conn()
      |> init_test_session(%{pending_identity: get_session(asked, :pending_identity)})
      |> Plug.Conn.put_private(:plug_skip_csrf_protection, true)
    end

    setup do
      Req.Test.stub(Core.Engine, fn conn ->
        Req.Test.json(conn, %{"status" => "success", "data" => %{"id" => 1}})
      end)

      {:ok, user} = Accounts.upsert_from_oauth(github(41))
      %{user: user}
    end

    test "is asked first, then signing in to that account adds the new sign-in",
         %{user: user} do
      asked = callback(%{}, google(42, "OLA@example.com"))
      assert redirected_to(asked) == "/signin"
      assert get_session(asked, :user_id) == nil
      assert Cab.Repo.aggregate(Accounts.User, :count) == 1

      page = asked |> carrying() |> get(~p"/signin") |> html_response(200)
      assert page =~ "You may already have an account"
      assert page =~ ~s(id="signin-github")
      refute page =~ ~s(id="signin-google")
      assert page =~ ~s(id="separate-account-form")

      linked =
        callback(%{pending_identity: get_session(asked, :pending_identity)}, github(41))

      assert get_session(linked, :user_id) == user.id
      assert get_session(linked, :pending_identity) == nil
      assert Phoenix.Flash.get(linked.assigns.flash, :info) =~ "Google is now linked"
      assert Enum.map(Accounts.list_identities(user), & &1.provider) == ["github", "google"]
    end

    test "or makes a separate account when the person says so", %{user: user} do
      asked = callback(%{}, google(43, "ola@example.com"))
      separate = asked |> carrying() |> post(~p"/signin/separate")

      assert redirected_to(separate) == "/"
      new_id = get_session(separate, :user_id)
      assert new_id && new_id != user.id
      assert Cab.Repo.aggregate(Accounts.User, :count) == 2
    end

    test "Sign in another way drops the question" do
      asked = callback(%{}, google(44, "ola@example.com"))
      back = asked |> carrying() |> get(~p"/signin?start_over=1")
      assert redirected_to(back) == "/signin"
      assert get_session(back, :pending_identity) == nil
    end
  end

  test "an admin merges one person's two accounts", %{conn: conn} do
    admin = user_fixture(%{node_user_id: 621})
    admin = admin |> Ecto.Changeset.change(is_admin: true) |> Cab.Repo.update!()
    older = user_fixture(%{node_user_id: 622, username: "older-acc"})
    younger = user_fixture(%{node_user_id: 623})

    Req.Test.stub(Core.Engine, fn conn ->
      Req.Test.json(conn, %{"status" => "success", "data" => %{"moved" => 0}})
    end)

    done =
      conn
      |> signed_in(admin)
      |> post(~p"/admin/merge", %{first: younger.username, second: "older-acc"})

    assert redirected_to(done) == "/admin"
    assert Phoenix.Flash.get(done.assigns.flash, :info) =~ "merged into older-acc"
    assert Cab.Repo.get(Accounts.User, younger.id) == nil
  end

  test "the merge form names accounts by username or e-mail, and only shows with two or more",
       %{conn: conn} do
    admin = user_fixture() |> Ecto.Changeset.change(is_admin: true) |> Cab.Repo.update!()
    Cab.Repo.delete_all(from u in Accounts.User, where: u.id != ^admin.id)

    alone = conn |> signed_in(admin) |> get(~p"/admin") |> html_response(200)
    refute alone =~ ~s(id="merge-accounts-form")

    other = user_fixture()
    page = conn |> signed_in(admin) |> get(~p"/admin") |> html_response(200)
    assert page =~ ~s(id="merge-accounts-form")
    assert page =~ ~s(name="first")
    refute page =~ ~s(name="first_id")

    same =
      conn
      |> signed_in(admin)
      |> post(~p"/admin/merge", %{first: other.username, second: other.username})

    assert Phoenix.Flash.get(same.assigns.flash, :error) =~ "That is this account."

    unknown =
      conn
      |> signed_in(admin)
      |> post(~p"/admin/merge", %{first: other.username, second: "nobody"})

    assert Phoenix.Flash.get(unknown.assigns.flash, :error) =~
             ~s(No account has the username or e-mail "nobody".)
  end

  test "the display name: over-long or garbled is refused with the field named; invisible is none",
       %{conn: conn} do
    user = user_fixture(%{name: "Ann"})

    resp = conn |> signed_in(user) |> post(~p"/account", %{name: String.duplicate("x", 121)})

    assert Phoenix.Flash.get(resp.assigns.flash, :error) ==
             "Display name: 120 characters at most."

    resp = conn |> signed_in(user) |> post(~p"/account", %{name: "A\u0000nn"})

    assert Phoenix.Flash.get(resp.assigns.flash, :error) ==
             "Display name: Use plain text without control characters."

    assert Cab.Repo.reload(user).name == "Ann"

    conn |> signed_in(user) |> post(~p"/account", %{name: "\u200B\u00A0"})
    assert Cab.Repo.reload(user).name == nil
  end
end
