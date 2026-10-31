defmodule PublicWeb.ClubLookTest do
  @moduledoc """
  A club's logo, kept in cab: the clubs list and the club page show it
  from cab's address; without one they look as before.
  """
  use PublicWeb.ConnCase

  defp with_logo(club, logo) do
    club
    |> Ecto.Changeset.change(logo: logo)
    |> Cab.Repo.update!()
  end

  test "without a logo the clubs list and the club page look as before", %{conn: conn} do
    club = cab_club(cab_user(), %{name: "Plain Club", city: "Northport"})

    list = conn |> get(~p"/clubs") |> html_response(200)
    assert list =~ "Plain Club"
    refute list =~ "ua-logo"

    page = conn |> get(~p"/clubs/#{club.uuid}") |> html_response(200)
    assert page =~ "Plain Club"
    refute page =~ "ua-logo"
  end

  test "the clubs list and the club page show the logo from cab", %{conn: conn} do
    club =
      cab_user()
      |> cab_club(%{name: "Bright Club", city: "Southport"})
      |> with_logo("abcDEF123_-xyz.png")

    logo = CabWeb.Endpoint.url() <> "/uploads/abcDEF123_-xyz.png"
    assert PublicWeb.Clubs.logo_url(club) == logo

    list = conn |> get(~p"/clubs") |> html_response(200)
    assert list =~ ~r/<img[^>]* class="ua-logo" src="#{Regex.escape(logo)}" alt="">/

    page = conn |> get(~p"/clubs/#{club.uuid}") |> html_response(200)
    assert page =~ ~r/<img[^>]* class="ua-logo ua-logo--lg" src="#{Regex.escape(logo)}" alt="">/
  end
end
