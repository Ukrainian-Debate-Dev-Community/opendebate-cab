defmodule CabWeb.CabinetHomeTest do
  use CabWeb.ConnCase, async: true

  import Cab.Fixtures

  defp log_in(conn, user) do
    conn
    |> init_test_session(%{user_id: user.id})
    |> Plug.Conn.put_private(:plug_skip_csrf_protection, true)
  end

  test "signed-out home is the plain sign-in chrome + banner", %{conn: conn} do
    html = conn |> get(~p"/") |> html_response(200)

    assert html =~ ~s(class="chrome")
    assert html =~ "Sign in"
    assert html =~ ~s(href="/auth/github")
    assert html =~ ~s(class="banner info")
    refute html =~ "My clubs"
    refute html =~ "Sign out"
  end

  test "signed-in cabinet lists my clubs with role, status tag and member count", %{conn: conn} do
    user = user_fixture(%{username: "anna"})
    head = user_fixture()

    club = club_fixture(head, %{name: "Kyiv Debate Club", city: "Kyiv"})
    membership_fixture(user, club)

    pending_club = club_fixture(user_fixture(), %{name: "Lviv Debate Society"})
    {:ok, _} = Cab.Clubs.request_join(user, pending_club)

    html = conn |> log_in(user) |> get(~p"/") |> html_response(200)

    # account segments
    assert html =~ ~s(class="me")
    assert html =~ "anna"
    assert html =~ "Sign out"

    # my clubs: approved row opens; pending row is tagged, no link
    assert html =~ ~s(id="my-clubs")
    assert html =~ "Kyiv Debate Club"
    assert html =~ ~s(class="tag tag-ok")
    assert html =~ "active"
    assert html =~ ~s(href="/c/#{club.uuid}")
    assert html =~ "Lviv Debate Society"
    assert html =~ "request pending"
    refute html =~ ~s(href="/c/#{pending_club.uuid}")

    # member counts: head + anna = 2
    assert html =~ ~r/class="num">\s*2\s*</

    # my sessions ships with the table's empty state (M3 fills it)
    assert html =~ ~s(id="my-sessions")
    assert html =~ "Past sessions will appear here."
  end
end
