defmodule CabWeb.HeadInvitationsTest do
  @moduledoc """
  An admin invites someone to head a club by e-mail: a new club is
  headed by the admin until the invitee accepts; an existing club keeps
  its head until then. The link sends a signed-out person through the
  sign-in and makes the signed-in account the head.
  """
  use CabWeb.ConnCase, async: false

  import Cab.Fixtures
  import Swoosh.TestAssertions

  alias Cab.{Clubs, HeadInvitations, Repo}
  alias Cab.Clubs.HeadInvitation

  defp log_in(conn, user) do
    conn
    |> init_test_session(%{user_id: user.id})
    |> Plug.Conn.put_private(:plug_skip_csrf_protection, true)
  end

  defp admin_fixture(attrs \\ %{}) do
    attrs |> user_fixture() |> Ecto.Changeset.change(is_admin: true) |> Repo.update!()
  end

  # every engine call succeeds: organisations, owners, provisioning
  setup do
    Req.Test.stub(Core.Engine, fn conn ->
      status = if conn.method == "POST", do: 201, else: 200

      conn
      |> Plug.Conn.put_status(status)
      |> Req.Test.json(%{"status" => "success", "data" => %{"id" => 77, "name" => "x"}})
    end)

    :ok
  end

  defp token_from_email do
    assert_email_sent(fn email ->
      [_, token] = Regex.run(~r{/head-invitations/([A-Za-z0-9_-]+)}, email.text_body)
      send(self(), {:token, token})
      true
    end)

    assert_received {:token, token}
    token
  end

  test "creating a club with an existing account works as before", %{conn: conn} do
    admin = admin_fixture()
    head = user_fixture(%{username: "newhead-#{System.unique_integer([:positive])}"})

    resp =
      conn |> log_in(admin) |> post(~p"/admin/clubs", %{name: "Plain Club", head: head.username})

    assert redirected_to(resp) == "/admin"
    [club] = Clubs.list_clubs() |> Enum.filter(&(&1.name == "Plain Club"))
    assert Clubs.role_for(club, head) == :owner
    refute_email_sent()
  end

  test "creating a club with an e-mail: the admin heads it until the invitee accepts",
       %{conn: conn} do
    admin = admin_fixture()

    resp =
      conn
      |> log_in(admin)
      |> post(~p"/admin/clubs", %{
        name: "Invited Club",
        city: "Lviv",
        head: "olena@example.com",
        head_name: "Olena"
      })

    assert redirected_to(resp) == "/admin"
    assert Phoenix.Flash.get(resp.assigns.flash, :info) =~ "Olena is invited by e-mail"
    [club] = Clubs.list_clubs() |> Enum.filter(&(&1.name == "Invited Club"))
    assert Clubs.head_of(club).id == admin.id

    token = token_from_email()
    invitee = user_fixture()

    accepted = conn |> log_in(invitee) |> get(~p"/head-invitations/#{token}")
    assert redirected_to(accepted) == "/c/#{club.uuid}/owner"
    assert Clubs.head_of(club).id == invitee.id
    # the admin only stood in: they leave the club
    refute Repo.get_by(Clubs.Membership, club_id: club.id, user_id: admin.id)

    invitation = Repo.get_by!(HeadInvitation, club_id: club.id)
    assert invitation.accepted_at
    assert is_nil(invitation.email)
  end

  test "an invitation needs a name, and a non-address that matches no account is refused",
       %{conn: conn} do
    admin = admin_fixture()

    no_name =
      conn |> log_in(admin) |> post(~p"/admin/clubs", %{name: "X Club", head: "a@example.com"})

    assert Phoenix.Flash.get(no_name.assigns.flash, :error) =~ "Type their name"

    nobody = conn |> log_in(admin) |> post(~p"/admin/clubs", %{name: "Y Club", head: "nobody"})
    assert Phoenix.Flash.get(nobody.assigns.flash, :error) =~ "No account has that username"
    assert Clubs.list_clubs() |> Enum.filter(&(&1.name in ["X Club", "Y Club"])) == []
  end

  test "invisible or over-long names make nothing: no club, no invitation", %{conn: conn} do
    admin = admin_fixture()

    for {club_name, head_name} <- [
          {"\u200B\u00A0", "Nina"},
          {"Z Club", "\u200B\uFEFF"},
          {"Z Club", String.duplicate("x", 121)}
        ] do
      resp =
        conn
        |> log_in(admin)
        |> post(~p"/admin/clubs", %{name: club_name, head: "z@example.com", head_name: head_name})

      assert redirected_to(resp) == "/admin"
      assert Phoenix.Flash.get(resp.assigns.flash, :error)
    end

    resp =
      conn
      |> log_in(admin)
      |> post(~p"/admin/clubs", %{name: "\u200B", head: admin.username})

    assert Phoenix.Flash.get(resp.assigns.flash, :error) == "Club name: Fill this in."

    assert Clubs.list_clubs() |> Enum.filter(&(&1.name == "Z Club")) == []
    assert Repo.all(HeadInvitation) |> Enum.filter(&(&1.email == "z@example.com")) == []
    refute_email_sent()
  end

  test "changing the head by e-mail keeps the current head until acceptance", %{conn: conn} do
    admin = admin_fixture()
    head = user_fixture()
    club = club_fixture(head)

    resp =
      conn
      |> log_in(admin)
      |> post(~p"/admin/head", %{uuid: club.uuid, head: "taras@example.com", head_name: "Taras"})

    assert Phoenix.Flash.get(resp.assigns.flash, :info) =~ "the current head stays"
    assert Clubs.head_of(club).id == head.id

    token = token_from_email()
    invitee = user_fixture()
    conn |> log_in(invitee) |> get(~p"/head-invitations/#{token}")

    assert Clubs.head_of(club).id == invitee.id
    assert Clubs.role_for(club, head) == :member
  end

  test "signed out: the link leads to sign-in, and the sign-in makes them the head",
       %{conn: conn} do
    admin = admin_fixture()
    club = club_fixture(user_fixture())
    {:ok, _invitation, token} = HeadInvitations.invite(club, "ira@example.com", "Ira", admin)

    opened = get(conn, ~p"/head-invitations/#{token}")
    assert redirected_to(opened) == "/signin"
    assert get_session(opened, :head_invitation) == token

    signin = opened |> recycle() |> get(~p"/signin") |> html_response(200)
    assert signin =~ ~s(id="head-invitation-prompt")
    assert signin =~ club.name

    # an account the engine already knows, signing in with GitHub
    ira = user_fixture()
    uid = "gh-#{System.unique_integer([:positive])}"
    Repo.insert!(%Cab.Accounts.Identity{provider: "github", provider_uid: uid, user_id: ira.id})

    auth = %Ueberauth.Auth{
      provider: :github,
      uid: uid,
      info: %Ueberauth.Auth.Info{nickname: ira.username}
    }

    signed_in =
      build_conn()
      |> init_test_session(%{head_invitation: token})
      |> Phoenix.Controller.fetch_flash()
      |> Plug.Conn.assign(:ueberauth_auth, auth)
      |> CabWeb.AuthController.callback(%{})

    assert redirected_to(signed_in) == "/c/#{club.uuid}/owner"
    assert get_session(signed_in, :user_id) == ira.id
    assert Clubs.head_of(club).id == ira.id
    assert is_nil(get_session(signed_in, :head_invitation))
  end

  test "used, cancelled, expired and unknown links show a clear page", %{conn: conn} do
    admin = admin_fixture()
    club = club_fixture(user_fixture())

    {:ok, _, used} = HeadInvitations.invite(club, "u@example.com", "U", admin)
    {:ok, _} = HeadInvitations.accept(used, user_fixture())
    assert conn |> get(~p"/head-invitations/#{used}") |> html_response(410) =~ "already accepted"

    {:ok, invitation, cancelled} = HeadInvitations.invite(club, "c@example.com", "C", admin)
    {:ok, _} = HeadInvitations.cancel(invitation)
    assert conn |> get(~p"/head-invitations/#{cancelled}") |> html_response(410) =~ "cancelled"

    {:ok, invitation, expired} = HeadInvitations.invite(club, "e@example.com", "E", admin)

    invitation
    |> Ecto.Changeset.change(expires_at: DateTime.add(DateTime.utc_now(:second), -1, :day))
    |> Repo.update!()

    assert conn |> get(~p"/head-invitations/#{expired}") |> html_response(410) =~ "expired"
    assert conn |> get(~p"/head-invitations/nonsense") |> html_response(410) =~ "not valid"
  end

  test "a new invitation for the same club cancels the previous one" do
    admin = admin_fixture()
    club = club_fixture(user_fixture())
    {:ok, _, first} = HeadInvitations.invite(club, "one@example.com", "One", admin)
    {:ok, _, _second} = HeadInvitations.invite(club, "two@example.com", "Two", admin)

    assert HeadInvitations.by_token(first) == {:error, :cancelled}
  end

  test "a guest's personal link cannot head a club" do
    admin = admin_fixture()
    club = club_fixture(user_fixture())
    session = session_fixture(club)
    guest = user_fixture()
    link_fixture(guest, session)
    {:ok, _, token} = HeadInvitations.invite(club, "g@example.com", "G", admin)

    assert HeadInvitations.accept(token, guest) == {:error, :guest}
    assert {:ok, _} = HeadInvitations.by_token(token)
  end

  test "the admin page lists pending invitations; resend and cancel", %{conn: conn} do
    admin = admin_fixture()

    club =
      club_fixture(user_fixture(), %{name: "Pending Club #{System.unique_integer([:positive])}"})

    {:ok, invitation, old_token} = HeadInvitations.invite(club, "p@example.com", "Petro", admin)

    page = conn |> log_in(admin) |> get(~p"/admin") |> html_response(200)
    assert page =~ ~s(id="head-invitations")
    assert page =~ "p@example.com"

    resent = conn |> log_in(admin) |> post(~p"/admin/head-invitations/#{invitation.id}/resend")
    assert Phoenix.Flash.get(resent.assigns.flash, :info) =~ "A new link was e-mailed to Petro"
    new_token = token_from_email()
    assert new_token != old_token
    assert HeadInvitations.by_token(old_token) == {:error, :unknown}

    cancelled = conn |> log_in(admin) |> post(~p"/admin/head-invitations/#{invitation.id}/cancel")
    assert redirected_to(cancelled) == "/admin"
    assert HeadInvitations.by_token(new_token) == {:error, :cancelled}
    refute conn |> log_in(admin) |> get(~p"/admin") |> html_response(200) =~ "p@example.com"
  end

  test "when the e-mail cannot go out the admin gets the link", %{conn: conn} do
    mailer = Application.get_env(:core, Core.Mailer)
    Application.put_env(:core, Core.Mailer, adapter: Cab.FailingMailAdapter)
    on_exit(fn -> Application.put_env(:core, Core.Mailer, mailer) end)

    admin = admin_fixture()
    club = club_fixture(user_fixture())

    resp =
      conn
      |> log_in(admin)
      |> post(~p"/admin/head", %{uuid: club.uuid, head: "fail@example.com", head_name: "Fail"})

    error = Phoenix.Flash.get(resp.assigns.flash, :error)
    assert error =~ "could not be sent"
    assert error =~ "/head-invitations/"
  end

  test "only admins reach the invitation actions", %{conn: conn} do
    admin = admin_fixture()
    club = club_fixture(user_fixture())
    {:ok, invitation, _} = HeadInvitations.invite(club, "x@example.com", "X", admin)
    plain = user_fixture()

    for path <- [
          ~p"/admin/head-invitations/#{invitation.id}/resend",
          ~p"/admin/head-invitations/#{invitation.id}/cancel"
        ] do
      assert conn |> log_in(plain) |> post(path) |> response(404)
    end
  end
end
