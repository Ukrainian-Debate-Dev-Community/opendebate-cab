defmodule PublicWeb.ManageTest do
  use PublicWeb.ConnCase

  alias Public.{Events, News, Roles}

  defp editor do
    user = cab_user(%{name: "Iryna Editor"})
    {:ok, _} = Roles.grant(user.id)
    user
  end

  test "signed out, /manage sends to cab's sign-in and back", %{conn: conn} do
    to = conn |> get(~p"/manage/news?page=2") |> redirected_to(302)
    cab = Application.fetch_env!(:public, :cab_url)
    assert String.starts_with?(to, cab <> "/signin?return_to=")

    back =
      to |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query() |> Map.fetch!("return_to")

    assert back == PublicWeb.Endpoint.url() <> "/manage/news?page=2"

    # a form sent without a session is simply not there
    assert_error_sent 404, fn -> post(conn, ~p"/manage/calendar/public", %{}) end
  end

  test "/manage does not exist for anyone signed in without the role", %{conn: conn} do
    unknown = conn |> get("/no-such-page") |> html_response(404)
    assert unknown =~ "Page not found"
    assert unknown =~ ~s(class="ua-error")

    {404, _headers, page} =
      assert_error_sent(404, fn -> conn |> cab_sign_in(cab_user()) |> get(~p"/manage") end)

    assert page =~ "Page not found"
    assert page =~ ~s(class="ua-error")
    assert page =~ "LeagueSite"
    refute page =~ "manage"

    {_status, headers, _body} =
      assert_error_sent 404, fn -> conn |> cab_sign_in(cab_user()) |> get(~p"/manage/news") end

    refute Enum.any?(headers, fn {k, _} -> k == "set-cookie" end)
  end

  test "a tampered cab cookie is no one: off to the sign-in", %{conn: conn} do
    conn = Plug.Test.put_req_cookie(conn, CabWeb.Session.cookie_key(), "forged")
    assert conn |> get(~p"/manage") |> redirected_to(302) =~ "/signin?return_to="
  end

  test "content managers and cab admins get the ribbon", %{conn: conn} do
    html = conn |> cab_sign_in(editor()) |> get(~p"/manage") |> html_response(200)
    assert html =~ "ua-cmbar"
    assert html =~ "Content manager"
    assert html =~ "Iryna Editor"
    refute html =~ ~s(href="/manage/people")

    admin_html =
      conn |> cab_sign_in(cab_user(%{is_admin: true})) |> get(~p"/manage") |> html_response(200)

    assert admin_html =~ ~s(href="/manage/people")
  end

  test "people is for cab admins: grant and revoke", %{conn: conn} do
    assert_error_sent 404, fn -> conn |> cab_sign_in(editor()) |> get(~p"/manage/people") end

    admin = cab_user(%{is_admin: true})
    newcomer = cab_user(%{username: "mariia", email: "mariia@example.org"})
    signed = cab_sign_in(conn, admin)

    assert signed |> get(~p"/manage/people") |> html_response(200) =~
             "Grant the content-manager role"

    assert signed
           |> post(~p"/manage/people", %{"login" => "Mariia@example.org"})
           |> redirected_to() ==
             "/manage/people"

    assert Roles.content_manager?(newcomer.id)

    signed |> delete(~p"/manage/people/#{newcomer.id}")
    refute Roles.content_manager?(newcomer.id)
  end

  test "news: a draft until it is published", %{conn: conn} do
    signed = cab_sign_in(conn, editor())

    resp =
      post(signed, ~p"/manage/news", %{
        "post" => %{"title" => "Season opens", "rubric" => "announcements", "body" => "Hello"}
      })

    post = News.list_all() |> hd()
    assert redirected_to(resp) == "/manage/news/#{post.id}/edit"
    assert_error_sent 404, fn -> get(conn, ~p"/news/season-opens") end

    post(signed, ~p"/manage/news/#{post.id}/publish")
    assert conn |> get(~p"/news/season-opens") |> html_response(200) =~ "Season opens"
  end

  test "events: private ones show only in the manager's calendar", %{conn: conn} do
    signed = cab_sign_in(conn, editor())
    today = Date.to_iso8601(Date.utc_today())

    post(signed, ~p"/manage/events", %{
      "event" => %{"title" => "Jury briefing", "starts_on" => today, "visibility" => "private"}
    })

    assert signed |> get(~p"/manage/calendar") |> html_response(200) =~ "Jury briefing"
    refute conn |> get(~p"/calendar") |> html_response(200) =~ "Jury briefing"

    [event] = Events.upcoming_all(Date.utc_today())
    post(signed, ~p"/manage/events/#{event.id}/visibility", %{"visibility" => "public"})
    assert conn |> get(~p"/calendar") |> html_response(200) =~ "Jury briefing"
  end
end
