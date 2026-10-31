defmodule PublicWeb.RequiredFieldsTest do
  @moduledoc """
  The /manage forms: a required field is not filled by spaces,
  no-break spaces or zero-width characters; text is trimmed, capped
  and free of control characters, and a refused form re-renders
  instead of failing.
  """
  use PublicWeb.ConnCase

  alias Public.{Events, News, Roles, Tags}

  @blanks ["   ", "\u00A0\u00A0", "\u200B", " \uFEFF\u200D "]

  defp signed(conn) do
    user = cab_user(%{name: "Iryna Editor"})
    {:ok, _} = Roles.grant(user.id)
    cab_sign_in(conn, user)
  end

  defp today, do: Date.to_iso8601(Date.utc_today())

  describe "news" do
    test "a blank title is refused", %{conn: conn} do
      signed = signed(conn)

      for blank <- @blanks do
        html =
          signed |> post(~p"/manage/news", %{"post" => %{"title" => blank}}) |> html_response(200)

        assert html =~ "Fill this in."
      end

      assert News.list_all() == []
    end

    test "text is trimmed; blank optional fields are empty", %{conn: conn} do
      post(signed(conn), ~p"/manage/news", %{
        "post" => %{
          "title" => "\u200B Season opens\u00A0",
          "slug" => "\u200B",
          "summary" => " \u00A0",
          "body" => "\uFEFF Line one\r\nLine two\n",
          "image_alt" => "\u200B"
        }
      })

      [post] = News.list_all()
      assert post.title == "Season opens"
      assert post.slug == "season-opens"
      assert post.summary == nil
      assert post.body == "Line one\nLine two"
      assert post.image_alt == nil
    end

    test "a blank body stays an empty text", %{conn: conn} do
      signed = signed(conn)
      post(signed, ~p"/manage/news", %{"post" => %{"title" => "Draft", "body" => "Text"}})
      [post] = News.list_all()

      put(signed, ~p"/manage/news/#{post.id}", %{"post" => %{"body" => "   "}})
      assert News.get!(post.id).body == ""

      put(signed, ~p"/manage/news/#{post.id}", %{"post" => %{"body" => "\u200B"}})
      assert News.get!(post.id).body == ""
    end

    test "over-long text and control characters are refused", %{conn: conn} do
      signed = signed(conn)

      for {field, value} <- [
            {"title", String.duplicate("x", 201)},
            {"slug", String.duplicate("x", 201)},
            {"image_alt", String.duplicate("x", 201)},
            {"summary", String.duplicate("x", 1001)},
            {"body", String.duplicate("x", 20_001)}
          ] do
        html =
          signed
          |> post(~p"/manage/news", %{"post" => Map.merge(%{"title" => "T"}, %{field => value})})
          |> html_response(200)

        assert html =~ "characters at most.", field
      end

      for {field, value} <- [
            {"title", "Bad\u0000title"},
            {"summary", "a\u0007b"},
            {"image_alt", "a\nb"}
          ] do
        html =
          signed
          |> post(~p"/manage/news", %{"post" => Map.merge(%{"title" => "T"}, %{field => value})})
          |> html_response(200)

        assert html =~ "Use plain text without control characters.", field
      end

      assert News.list_all() == []
    end
  end

  describe "events" do
    test "a blank title is refused", %{conn: conn} do
      signed = signed(conn)

      for blank <- @blanks do
        html =
          signed
          |> post(~p"/manage/events", %{"event" => %{"title" => blank, "starts_on" => today()}})
          |> html_response(200)

        assert html =~ "Fill this in."
      end

      assert Events.upcoming_all(Date.utc_today()) == []
    end

    test "text is trimmed; blank optional fields are empty", %{conn: conn} do
      post(signed(conn), ~p"/manage/events", %{
        "event" => %{
          "title" => "\u00A0Open Cup\u200B",
          "starts_on" => today(),
          "city" => "\u200B",
          "format" => " BP\u00A0",
          "link" => " https://example.org/cup\uFEFF",
          "details" => "\u200B\n",
          "language" => "other",
          "language_other" => "\u00A0Polish "
        }
      })

      [event] = Events.upcoming_all(Date.utc_today())
      assert event.title == "Open Cup"
      assert {event.city, event.format, event.details} == {nil, "BP", nil}
      assert event.link == "https://example.org/cup"
      assert event.language_other == "Polish"
    end

    test "over-long text and control characters are refused", %{conn: conn} do
      signed = signed(conn)

      for {field, value} <- [
            {"title", String.duplicate("x", 201)},
            {"city", String.duplicate("x", 81)},
            {"format", String.duplicate("x", 81)},
            {"link", "https://example.org/" <> String.duplicate("x", 240)},
            {"details", String.duplicate("x", 5001)},
            {"title", "Cup\u0000"},
            {"city", "Northport\tSouthport"},
            {"details", "a\u001Bb"}
          ] do
        html =
          signed
          |> post(~p"/manage/events", %{
            "event" => Map.merge(%{"title" => "Cup", "starts_on" => today()}, %{field => value})
          })
          |> html_response(200)

        assert html =~ ~r/characters at most\.|Use plain text without control characters\./, field
      end

      assert Events.upcoming_all(Date.utc_today()) == []
    end
  end

  describe "tags" do
    test "blank, over-long and control-character names are refused", %{conn: conn} do
      signed = signed(conn)

      for name <- @blanks ++ [String.duplicate("x", 41), "a\u0000b"] do
        signed
        |> post(~p"/manage/tags", %{"tag" => %{"name" => name, "color" => "red"}})
        |> html_response(200)
      end

      assert Tags.list() == []

      post(signed, ~p"/manage/tags", %{
        "tag" => %{"name" => "\u200BNeeds review\u00A0", "color" => "red"}
      })

      assert [%{name: "Needs review"}] = Tags.list()
    end
  end
end
