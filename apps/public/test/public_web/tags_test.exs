defmodule PublicWeb.TagsTest do
  @moduledoc """
  Private tags: content managers keep them on /manage/tags and put them
  on events and news; they show and filter only under /manage, never on
  a public page or the feed.
  """
  use PublicWeb.ConnCase

  alias Public.{Events, News, Roles, Tags}

  defp editor do
    user = cab_user(%{name: "Iryna Editor"})
    {:ok, _} = Roles.grant(user.id)
    user
  end

  test "a content manager creates, edits and deletes them", %{conn: conn} do
    signed = cab_sign_in(conn, editor())
    assert signed |> get(~p"/manage") |> html_response(200) =~ ~s(href="/manage/tags")

    resp =
      post(signed, ~p"/manage/tags", %{"tag" => %{"name" => " Needs review ", "color" => "red"}})

    assert redirected_to(resp) == "/manage/tags"
    [tag] = Tags.list()
    assert {tag.name, tag.color} == {"Needs review", "red"}

    assert signed |> get(~p"/manage/tags") |> html_response(200) =~
             ~s(class="ua-label ua-label--red">Needs review)

    assert signed |> get(~p"/manage/tags/#{tag.id}/edit") |> html_response(200) =~ "Needs review"

    put(signed, ~p"/manage/tags/#{tag.id}", %{
      "tag" => %{"name" => "Confirmed", "color" => "green"}
    })

    assert %{name: "Confirmed", color: "green"} = Tags.get!(tag.id)

    assert signed
           |> post(~p"/manage/tags", %{"tag" => %{"name" => "Odd", "color" => "pink"}})
           |> html_response(200)

    assert length(Tags.list()) == 1

    delete(signed, ~p"/manage/tags/#{tag.id}")
    assert Tags.list() == []
  end

  test "they do not exist for anyone else", %{conn: conn} do
    {:ok, tag} = Tags.create(%{"name" => "Secret", "color" => "blue"})

    # signed out: to cab's sign-in for a page, nothing for a change
    assert conn |> get(~p"/manage/tags") |> redirected_to(302) =~ "/signin?return_to="

    for signed <- [conn, cab_sign_in(conn, cab_user())] do
      assert_error_sent 404, fn ->
        post(signed, ~p"/manage/tags", %{"tag" => %{"name" => "x"}})
      end

      assert_error_sent 404, fn -> delete(signed, ~p"/manage/tags/#{tag.id}") end
    end

    assert_error_sent 404, fn -> conn |> cab_sign_in(cab_user()) |> get(~p"/manage/tags") end

    assert [_] = Tags.list()
  end

  test "they show on /manage and never on public pages or the feed", %{conn: conn} do
    signed = cab_sign_in(conn, editor())
    {:ok, tag} = Tags.create(%{"name" => "Needs review", "color" => "orange"})
    today = Date.to_iso8601(Date.utc_today())

    post(signed, ~p"/manage/events", %{
      "event" => %{"title" => "Open Cup", "starts_on" => today, "tag_ids" => ["", "#{tag.id}"]}
    })

    post(signed, ~p"/manage/news", %{
      "post" => %{"title" => "Season opens", "tag_ids" => ["#{tag.id}"]}
    })

    [post] = News.list_all()
    {:ok, _} = News.publish(post, 1)

    for path <- ["/", "/news", "/news/season-opens", "/calendar", "/calendar.ics"] do
      body = conn |> get(path) |> response(200)
      assert body =~ ~r/Open Cup|Season opens/
      refute body =~ "Needs review", "#{path} shows a private tag"
      refute body =~ "ua-label", "#{path} shows a private tag"
    end

    for path <- ["/manage", "/manage/news", "/manage/calendar"] do
      assert signed |> get(path) |> html_response(200) =~ "Needs review", path
    end

    [event] = Events.upcoming_all(Date.utc_today())
    put(signed, ~p"/manage/events/#{event.id}", %{"event" => %{"tag_ids" => [""]}})
    assert Events.get!(event.id).tags == []
  end

  test "?tag= filters the news and the calendar", %{conn: conn} do
    signed = cab_sign_in(conn, editor())
    {:ok, tag} = Tags.create(%{"name" => "Stage two", "color" => "teal"})
    today = Date.utc_today()

    {:ok, _} = News.create(%{"title" => "Tagged post", "tag_ids" => ["#{tag.id}"]}, 1)
    {:ok, _} = News.create(%{"title" => "Plain post"}, 1)

    {:ok, _} =
      Events.create(
        %{"title" => "Tagged cup", "starts_on" => today, "tag_ids" => ["#{tag.id}"]},
        1
      )

    {:ok, _} = Events.create(%{"title" => "Plain cup", "starts_on" => today}, 1)

    html = signed |> get(~p"/manage/news?#{[tag: tag.id]}") |> html_response(200)
    assert html =~ "Tagged post"
    refute html =~ "Plain post"

    html = signed |> get(~p"/manage/calendar?#{[tag: tag.id]}") |> html_response(200)
    assert html =~ "Tagged cup"
    refute html =~ "Plain cup"

    for junk <- ["", "abc", "999999"] do
      html = signed |> get(~p"/manage/news?#{[tag: junk]}") |> html_response(200)
      assert html =~ "Tagged post" and html =~ "Plain post"
    end
  end
end
