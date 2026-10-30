defmodule PublicWeb.ErrorHTML do
  @moduledoc """
  Error pages in the site's frame: one centered card under the tenant's
  wordmark with the way back home, like the sign-in card. A 404
  never says why, so /manage stays unknown to anyone without access.
  """
  use PublicWeb, :html

  def render(template, _assigns) do
    code = template |> String.split(".") |> hd()

    assigns = %{
      code: code,
      title: title(code),
      name: Public.Tenant.get(:name),
      lead: lead(code),
      locale: Gettext.get_locale(PublicWeb.Gettext)
    }

    ~H"""
    <!DOCTYPE html>
    <html lang={@locale}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{@title} | {@name}</title>
        <script>
          try {
            const theme = localStorage.getItem("public-theme")
            if (theme === "light" || theme === "dark") document.documentElement.dataset.theme = theme
          } catch (_e) {}
        </script>
        <link rel="stylesheet" href={~p"/css/app.css"} />
        <script defer src={~p"/js/site.js"}>
        </script>
      </head>
      <body>
        <div class="ua">
          <.site_header />
          <main class="ua-main">
            <div class="ua-error">
              <.wordmark class="ua-error-mark" />
              <span class="ua-kicker">{@code}</span>
              <h1>{@title}</h1>
              <p>{@lead}</p>
              <a class="ua-btn ua-btn--line ua-error-back" href={~p"/"}>
                {gettext("Back to the home page")}
              </a>
            </div>
          </main>
          <.site_footer />
        </div>
      </body>
    </html>
    """
  end

  defp title("404"), do: gettext("Page not found")
  defp title("500"), do: gettext("Something went wrong")
  defp title(code), do: Phoenix.Controller.status_message_from_template(code <> ".html")

  defp lead("404"),
    do: gettext("There is nothing at this address. It may have moved, or the link is mistyped.")

  defp lead("500"), do: gettext("We could not show this page. Please try again in a minute.")
  defp lead(_code), do: gettext("This page cannot be shown.")
end
