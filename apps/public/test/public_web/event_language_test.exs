defmodule PublicWeb.EventLanguageTest do
  @moduledoc "An event's language: Ukrainian, English or another one named."
  use PublicWeb.ConnCase

  alias Public.{Events, Roles}

  defp editor do
    user = cab_user(%{name: "Iryna Editor"})
    {:ok, _} = Roles.grant(user.id)
    user
  end

  test "saved, shown on the public calendar and in the feed; other's name only for other",
       %{conn: conn} do
    signed = cab_sign_in(conn, editor())
    today = Date.to_iso8601(Date.utc_today())

    post(signed, ~p"/manage/events", %{
      "event" => %{
        "title" => "Warsaw Open",
        "starts_on" => today,
        "language" => "other",
        "language_other" => "Polish"
      }
    })

    [event] = Events.upcoming_all(Date.utc_today())
    assert {event.language, event.language_other} == {"other", "Polish"}
    assert conn |> get(~p"/calendar") |> html_response(200) =~ "Polish"
    assert conn |> get(~p"/calendar.ics") |> response(200) =~ "DESCRIPTION:Language: Polish"

    put(signed, ~p"/manage/events/#{event.id}", %{
      "event" => %{"language" => "en", "language_other" => "Polish"}
    })

    event = Events.get!(event.id)
    assert {event.language, event.language_other} == {"en", nil}
    html = conn |> get(~p"/calendar") |> html_response(200)
    assert html =~ "English"
    refute html =~ "Polish"
  end

  test "an unknown language is refused", %{conn: conn} do
    signed = cab_sign_in(conn, editor())

    signed
    |> post(~p"/manage/events", %{
      "event" => %{"title" => "X", "starts_on" => "2026-11-01", "language" => "klingon"}
    })
    |> html_response(200)

    assert Events.upcoming_all(~D[2026-01-01]) == []
  end
end
