defmodule CabWeb.LiveScopeTest do
  use Cab.DataCase, async: true

  import Cab.Fixtures

  alias CabWeb.LiveScope
  alias Phoenix.LiveView.Socket

  defp socket, do: %Socket{assigns: %{__changed__: %{}, flash: %{}}}

  test "unknown or archived club is a 404; anonymous has the public role" do
    assert_raise CabWeb.NotFoundError, fn ->
      LiveScope.on_mount(:club, %{"club_uuid" => Ecto.UUID.generate()}, %{}, socket())
    end

    club = club_fixture(user_fixture())
    assert {:cont, s} = LiveScope.on_mount(:club, %{"club_uuid" => club.uuid}, %{}, socket())
    assert s.assigns.club_role == :public
    assert s.assigns.current_user == nil

    {:ok, _} = Cab.Clubs.archive_club(club)

    assert_raise CabWeb.NotFoundError, fn ->
      LiveScope.on_mount(:club, %{"club_uuid" => club.uuid}, %{}, socket())
    end
  end

  test "the owner gate follows the ladder: wall, 403, pass" do
    head = user_fixture()
    club = club_fixture(head)
    params = %{"club_uuid" => club.uuid}

    {:cont, anon} = LiveScope.on_mount(:club, params, %{}, socket())
    assert {:halt, _redirected} = LiveScope.on_mount(:owner, params, %{}, anon)

    member = user_fixture()
    membership_fixture(member, club)
    {:cont, as_member} = LiveScope.on_mount(:club, params, %{"user_id" => member.id}, socket())

    assert_raise CabWeb.ForbiddenError, fn ->
      LiveScope.on_mount(:owner, params, %{}, as_member)
    end

    {:cont, as_head} = LiveScope.on_mount(:club, params, %{"user_id" => head.id}, socket())
    assert {:cont, _} = LiveScope.on_mount(:owner, params, %{}, as_head)
  end
end
