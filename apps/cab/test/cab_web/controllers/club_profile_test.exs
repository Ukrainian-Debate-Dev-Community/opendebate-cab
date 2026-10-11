defmodule CabWeb.ClubProfileTest do
  @moduledoc """
  The club head keeps the club's format, languages and audience on the
  club edit page; the club page, the directory and the public club API
  show them.
  """
  use CabWeb.ConnCase, async: true

  import Cab.Fixtures

  defp log_in(conn, user), do: init_test_session(conn, %{user_id: user.id})

  setup do
    head = user_fixture()
    %{head: head, club: club_fixture(head, %{name: "Kyiv Debate Club", city: "Kyiv"})}
  end

  test "the head ticks format, language and audience; unticking all clears them",
       %{conn: conn, head: head, club: club} do
    html = conn |> log_in(head) |> get(~p"/c/#{club.uuid}/owner") |> html_response(200)
    assert html =~ ~s(name="formats[]")
    assert html =~ ~s(name="languages[]")
    assert html =~ ~s(name="audiences[]")

    conn
    |> log_in(head)
    |> post(~p"/c/#{club.uuid}/owner/club", %{
      name: club.name,
      formats: ["bp"],
      languages: ["uk", "en"],
      audiences: ["university", "open"]
    })

    club = Cab.Clubs.get_by_uuid(club.uuid)
    assert club.formats == ["bp"]
    assert club.languages == ["uk", "en"]
    assert club.audiences == ["university", "open"]

    conn |> log_in(head) |> post(~p"/c/#{club.uuid}/owner/club", %{name: club.name})

    club = Cab.Clubs.get_by_uuid(club.uuid)
    assert {club.formats, club.languages, club.audiences} == {[], [], []}
  end

  test "the club page and the directory show them", %{conn: conn, club: club} do
    {:ok, _} =
      Cab.Clubs.update_club(club, %{
        formats: ["bp", "apf"],
        languages: ["uk", "en"],
        audiences: ["university", "open"]
      })

    page = conn |> get(~p"/c/#{club.uuid}") |> html_response(200)
    assert page =~ "Format: BP, APF"
    assert page =~ "Language: Ukrainian, English"
    assert page =~ "Audience: university students, open to all"

    directory = conn |> get(~p"/") |> html_response(200)
    assert directory =~ "BP, APF"
  end

  test "GET /api/v1/clubs lists every club that is not archived, public profile only",
       %{conn: conn, head: head, club: club} do
    {:ok, _} = Cab.Clubs.update_club(club, %{formats: ["bp"], is_private: true})
    archived = club_fixture(head, %{name: "Gone"})
    {:ok, _} = Cab.Clubs.archive_club(archived)

    %{"clubs" => clubs} = conn |> get(~p"/api/v1/clubs") |> json_response(200)

    assert [listed] = Enum.filter(clubs, &(&1["uuid"] == club.uuid))
    assert listed["formats"] == ["bp"]
    assert listed["city"] == "Kyiv"
    refute Map.has_key?(listed, "members")
    refute Enum.any?(clubs, &(&1["uuid"] == archived.uuid))
  end

  test "PATCH keeps the fields it is not given and refuses unknown values",
       %{conn: conn, head: head, club: club} do
    {:ok, _} = Cab.Clubs.update_club(club, %{languages: ["uk"]})

    body =
      conn
      |> log_in(head)
      |> patch(~p"/api/v1/clubs/#{club.uuid}", %{formats: ["apf"]})
      |> json_response(200)

    assert body["formats"] == ["apf"]
    assert body["languages"] == ["uk"]

    assert conn
           |> log_in(head)
           |> patch(~p"/api/v1/clubs/#{club.uuid}", %{formats: ["chess"]})
           |> json_response(422)
  end
end
