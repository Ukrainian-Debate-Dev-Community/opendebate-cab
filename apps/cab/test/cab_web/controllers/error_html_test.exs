defmodule CabWeb.ErrorHTMLTest do
  use CabWeb.ConnCase, async: true

  import Phoenix.Template, only: [render_to_string: 4]
  import Cab.Fixtures

  test "raised errors render the branded page" do
    html = render_to_string(CabWeb.ErrorHTML, "404", "html", [])
    assert html =~ "Not found"
    assert html =~ ~s(class="error-page")

    assert render_to_string(CabWeb.ErrorHTML, "500", "html", []) =~ "Something went wrong"
  end

  test "controller 404s and 403s render the same page, not bare text", %{conn: conn} do
    # an unknown club
    assert html_response(get(conn, "/c/#{Ecto.UUID.generate()}"), 404) =~ "Not found"

    # an owner page for a non-member
    club = club_fixture(user_fixture())

    denied =
      conn
      |> init_test_session(%{user_id: user_fixture().id})
      |> get(~p"/c/#{club.uuid}/owner")

    assert html_response(denied, 403) =~ "Not allowed"
  end
end
