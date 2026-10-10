defmodule CabWeb.ErrorHTML do
  @moduledoc """
  Every HTML error — raised (404/403 from live pages, 500) or sent by a
  controller through `respond/3` — renders the same branded page.
  """
  use CabWeb, :html

  import Plug.Conn, only: [halt: 1, put_status: 2]
  import Phoenix.Controller, only: [put_view: 2, render: 3]

  embed_templates "error_html/*"

  defp page_copy(403), do: {gettext("Not allowed"), gettext("This page is not open to your account.")}
  defp page_copy(404), do: {gettext("Not found"), gettext("There is nothing at this address.")}

  defp page_copy(500),
    do: {gettext("Something went wrong"), gettext("The error is logged — try again in a moment.")}

  defp page_copy(_status), do: nil

  def render(template, _assigns) do
    status = template |> String.split(".") |> hd() |> String.to_integer()

    {heading, message} =
      page_copy(status) || {Phoenix.Controller.status_message_from_template(template), ""}

    error(%{heading: heading, message: message})
  end

  @doc "Halts a controller with the branded error page for `status`."
  def respond(conn, status, message \\ nil) when status in [403, 404] do
    {heading, default} = page_copy(status)

    conn
    |> put_status(status)
    |> put_view(html: __MODULE__)
    |> render(:error, heading: heading, message: message || default)
    |> halt()
  end
end
