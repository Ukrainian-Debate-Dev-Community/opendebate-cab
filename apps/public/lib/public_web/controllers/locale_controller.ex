defmodule PublicWeb.LocaleController do
  @moduledoc "The header's language menu: remember the choice, go back where you were."
  use PublicWeb, :controller

  @year 60 * 60 * 24 * 365

  # GET /locale/:locale
  def set(conn, %{"locale" => locale}) do
    case PublicWeb.Locale.chosen(locale) do
      nil ->
        raise PublicWeb.NotFound

      locale ->
        conn
        |> put_resp_cookie(PublicWeb.Locale.cookie(), locale, max_age: @year, same_site: "Lax")
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
