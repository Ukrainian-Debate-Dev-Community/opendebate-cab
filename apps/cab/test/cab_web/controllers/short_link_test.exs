defmodule CabWeb.ShortLinkTest do
  use CabWeb.ConnCase, async: true

  import Cab.Fixtures

  alias Cab.ShortLinks
  alias Cab.ShortLinks.ShortLink

  defp code(session) do
    {:ok, link} = ShortLinks.link(session)
    link.code
  end

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

  test "/<code> opens the session; /<code>/<n> opens room n", %{
    conn: conn,
    club: club,
    session: session
  } do
    assert redirected_to(get(conn, "/#{code(session)}")) ==
             "/c/#{club.uuid}/s/#{session.uuid}"

    # rooms are numbered in creation order: engine room 72 is R1
    assert redirected_to(get(conn, "/#{code(session)}/1")) ==
             "/c/#{club.uuid}/s/#{session.uuid}/rooms/72"

    assert redirected_to(get(conn, "/#{code(session)}/2")) ==
             "/c/#{club.uuid}/s/#{session.uuid}/rooms/90"

    missing = get(conn, "/#{code(session)}/7")
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
    assert html =~ "/#{code(session)}"
  end

  test "the room page offers its card: the room's data and the short link's QR",
       %{conn: conn, club: club, session: session} do
    html = conn |> get(~p"/c/#{club.uuid}/s/#{session.uuid}/rooms/72") |> html_response(200)
    assert html =~ ~s(phx-hook="ShareCard")
    # two columns, picture and text, each copied by a click; no buttons
    assert html =~ ~s(data-card-image)
    assert html =~ ~s(data-card-text)
    assert html =~ "Click the picture or the text to copy it"
    refute html =~ "Save image"

    [json] = Regex.run(~r/data-card="([^"]*)"/, html, capture: :all_but_first)
    card = json |> String.replace("&quot;", "\"") |> Jason.decode!()
    assert card["room"] == "R1"
    # people by side and the adjudicators; team names stay internal
    assert is_list(card["sides"])
    assert is_list(card["judges"])
    refute Map.has_key?(card, "teams")
    assert card["link"] =~ "/#{code(session)}/1"

    assert card["qr"] ==
             CabWeb.QR.matrix(card["link"])
             |> Enum.map(fn row -> Enum.map_join(row, &if(&1, do: "1", else: "0")) end)
  end

  test "rooms recorded at creation resolve without asking the engine", %{conn: conn, club: club} do
    session = session_fixture(club, engine_event_id: 12)

    session =
      session |> Ecto.Changeset.change(room_ids: [55, 56]) |> Cab.Repo.update!()

    Req.Test.stub(Core.Engine, fn _conn -> raise "the engine must not be asked" end)

    assert redirected_to(get(conn, "/#{code(session)}/2")) ==
             "/c/#{club.uuid}/s/#{session.uuid}/rooms/56"
  end

  test "a code moved over from before keeps opening its session", %{conn: conn, club: club} do
    session = session_fixture(club, engine_event_id: 13)
    Cab.Repo.insert!(%ShortLink{code: "k7m2q9", session_id: session.id})

    assert code(session) == "k7m2q9"
    assert redirected_to(get(conn, "/k7m2q9")) == "/c/#{club.uuid}/s/#{session.uuid}"
  end

  test "paths and own-host URLs shorten to one link each", %{conn: conn, club: club} do
    path = "/c/#{club.uuid}/standings/teams?session=abc#top"
    url = ShortLinks.short_url(path)
    assert url == ShortLinks.short_url(path)
    assert url == ShortLinks.short_url(CabWeb.Endpoint.url() <> path)

    "/" <> code = String.replace_prefix(url, CabWeb.Endpoint.url(), "")
    assert redirected_to(get(conn, "/" <> code)) == path
  end

  test "room numbers only follow session links", %{conn: conn} do
    {:ok, link} = ShortLinks.link("/standings/teams")
    assert get(conn, "/#{link.code}/1") |> response(404)
  end
end
