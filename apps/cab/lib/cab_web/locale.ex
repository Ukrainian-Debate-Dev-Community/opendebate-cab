defmodule CabWeb.Locale do
  @moduledoc """
  The page language: English by default, Ukrainian when the browser
  asks for it first, and whatever the footer switch picked (a cookie)
  above both. Set per request for controllers and per LiveView on
  mount, so templates translate with plain `gettext/1`.
  """
  import Plug.Conn

  @locales ~w(en uk)
  @cookie "cab_locale"

  def locales, do: @locales
  def cookie, do: @cookie

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn)

    locale =
      chosen(conn.cookies[@cookie]) || from_header(get_req_header(conn, "accept-language")) ||
        "en"

    Gettext.put_locale(CabWeb.Gettext, locale)
    conn |> put_session(:locale, locale) |> assign(:locale, locale)
  end

  def on_mount(:default, _params, session, socket) do
    locale = chosen(session["locale"]) || "en"
    Gettext.put_locale(CabWeb.Gettext, locale)
    {:cont, Phoenix.Component.assign(socket, :locale, locale)}
  end

  def chosen(locale) when locale in @locales, do: locale
  def chosen(_locale), do: nil

  # the first language in the browser's preference order that cab speaks
  def from_header([value | _]) when is_binary(value) do
    value
    |> String.split(",")
    |> Enum.map(fn part ->
      case String.split(String.trim(part), ";q=") do
        [tag, q] -> {tag, parse_q(q)}
        [tag] -> {tag, 1.0}
      end
    end)
    |> Enum.sort_by(&elem(&1, 1), :desc)
    |> Enum.find_value(fn {tag, _q} ->
      tag |> String.downcase() |> String.split("-") |> hd() |> chosen()
    end)
  end

  def from_header(_values), do: nil

  defp parse_q(q) do
    case Float.parse(q) do
      {value, _} -> value
      :error -> 0.0
    end
  end
end
