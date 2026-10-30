defmodule PublicWeb.Locale do
  @moduledoc """
  The page language: English by default, the other one (uk) when the
  browser asks for it first, and the header's language menu (its own cookie,
  never the sign-in session) above both. Public responses vary by
  that cookie and the browser's languages, so caches keep them apart.
  """
  import Plug.Conn

  @locales ~w(en uk)
  @cookie "public_locale"

  # the language menu: code, short label, the language's own name
  @names [
    {"en", "EN", "English"},
    {"uk", "UA", "\u0423\u043a\u0440\u0430\u0457\u043d\u0441\u044c\u043a\u0430"}
  ]

  def locales, do: @locales
  def names, do: @names
  def cookie, do: @cookie

  def short(locale),
    do: Enum.find_value(@names, "EN", fn {code, label, _} -> code == locale && label end)

  def init(opts), do: opts

  def call(conn, _opts) do
    conn = fetch_cookies(conn)

    locale =
      chosen(conn.cookies[@cookie]) || from_header(get_req_header(conn, "accept-language")) ||
        "en"

    Gettext.put_locale(PublicWeb.Gettext, locale)
    # cab's messages (Cab.Text form errors) in the same language
    Gettext.put_locale(CabWeb.Gettext, locale)

    conn
    |> assign(:locale, locale)
    |> put_resp_header("vary", "cookie, accept-language")
  end

  def chosen(locale) when locale in @locales, do: locale
  def chosen(_locale), do: nil

  # the first language in the browser's preference order the site speaks
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
