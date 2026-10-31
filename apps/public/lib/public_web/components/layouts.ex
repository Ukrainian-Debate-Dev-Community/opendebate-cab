defmodule PublicWeb.Layouts do
  @moduledoc "The one page frame: the public header, the ribbon under /manage, the footer."
  use PublicWeb, :html

  def root(assigns) do
    ~H"""
    <!DOCTYPE html>
    <html lang={Gettext.get_locale(PublicWeb.Gettext)}>
      <head>
        <meta charset="utf-8" />
        <meta name="viewport" content="width=device-width, initial-scale=1" />
        <title>{page_title(assigns)}</title>
        <script>
          // the header's theme choice, applied before the first paint
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
          <.site_header active={assigns[:active]} />
          <.ribbon
            :if={assigns[:access]}
            access={@access}
            manager={@manager}
            active={assigns[:manage_active]}
          />
          <main class="ua-main">
            <.flashes :if={assigns[:access]} flash={@flash} />
            {@inner_content}
          </main>
          <.site_footer />
        </div>
      </body>
    </html>
    """
  end

  defp page_title(%{page_title: title}) when is_binary(title),
    do: "#{title} | #{Public.Tenant.get(:name)}"

  defp page_title(_assigns), do: Public.Tenant.text(:title)

  attr :flash, :map, required: true

  defp flashes(assigns) do
    ~H"""
    <div :if={msg = Phoenix.Flash.get(@flash, :info)} class="ua-flash">{msg}</div>
    <div :if={msg = Phoenix.Flash.get(@flash, :error)} class="ua-flash ua-flash--error">{msg}</div>
    """
  end
end
