defmodule CabWeb.LocaleController do
  @moduledoc "The footer's language switch: remember the choice, go back where you were."
  use CabWeb, :controller

  @year 60 * 60 * 24 * 365

  # GET /locale/:locale
  def set(conn, %{"locale" => locale}) do
    case CabWeb.Locale.chosen(locale) do
      nil ->
        CabWeb.ErrorHTML.respond(conn, 404)

      locale ->
        conn
        |> put_resp_cookie(CabWeb.Locale.cookie(), locale, max_age: @year, same_site: "Lax")
        |> put_session(:locale, locale)
        |> redirect(to: back(conn))
    end
  end

  # only a path on this site, never somewhere else
  defp back(conn) do
    with [referer | _] <- get_req_header(conn, "referer"),
         %URI{host: host, path: path, query: query} when is_binary(path) <- URI.parse(referer),
         true <- host == conn.host do
      if query, do: "#{path}?#{query}", else: path
    else
      _ -> "/"
    end
  end
end
