defmodule CabWeb.ShortLinkTest do
  use CabWeb.ConnCase, async: true

  import Cab.Fixtures

  alias Cab.Sessions.Session

  defp ok(conn, data), do: Req.Test.json(conn, %{"status" => "success", "data" => data})

  setup do
    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})
    session = session_fixture(club, engine_event_id: 11)

    Req.Test.stub(Core.Engine, fn conn ->
      case conn.request_path do
        "/api/events/11" ->
          ok(conn, %{"id" => 11, "name" => "Short night", "status" => "ongoing"})

        "/api/events/11/rounds" ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        "/api/events/11/participants" ->
          ok(conn, [])

        "/api/rounds/21/rooms" ->
          ok(conn, [%{"id" => 90, "status" => "pending"}, %{"id" => 72, "status" => "pending"}])
      end
    end)

    %{club: club, session: session}
  end

  test "every session gets a six-character code with a digit" do
    for _ <- 1..200 do
      code = Session.generate_short_code()
      assert Session.short_code?(code)
    end

    refute Session.short_code?("signin")
    refute Session.short_code?("admin1")
    refute Session.short_code?("abcdef")
  end

  test "/<code> opens the session; /<code>/<n> opens room n", %{
    conn: conn,
    club: club,
    session: session
  } do
    assert redirected_to(get(conn, "/#{session.short_code}")) ==
             "/c/#{club.uuid}/s/#{session.uuid}"

    # rooms are numbered in creation order: engine room 72 is R1
    assert redirected_to(get(conn, "/#{session.short_code}/1")) ==
             "/c/#{club.uuid}/s/#{session.uuid}/rooms/72"

    assert redirected_to(get(conn, "/#{session.short_code}/2")) ==
             "/c/#{club.uuid}/s/#{session.uuid}/rooms/90"

    missing = get(conn, "/#{session.short_code}/7")
    assert redirected_to(missing) == "/c/#{club.uuid}/s/#{session.uuid}"
    assert Phoenix.Flash.get(missing.assigns.flash, :info) =~ "Room 7 is not open yet"
  end

  test "unknown codes and words are 404; named pages still win", %{conn: conn} do
    assert get(conn, "/zz9zz9") |> response(404)
    assert get(conn, "/nothere") |> response(404)
    assert get(conn, "/signin") |> html_response(200)
  end

  test "the session page shows its short link", %{conn: conn, club: club, session: session} do
    html = conn |> get(~p"/c/#{club.uuid}/s/#{session.uuid}") |> html_response(200)
    assert html =~ ~s(id="session-short-link")
    assert html =~ "/#{session.short_code}"
  end
end
