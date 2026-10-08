defmodule CabWeb.ErrorHTML do
  @moduledoc """
  Every HTML error — raised (404/403 from live pages, 500) or sent by a
  controller through `respond/3` — renders the same branded page.
  """
  use CabWeb, :html

  import Plug.Conn, only: [halt: 1, put_status: 2]
  import Phoenix.Controller, only: [put_view: 2, render: 3]

  embed_templates "error_html/*"

  @copy %{
    403 => {"Not allowed", "This page is not open to your account."},
    404 => {"Not found", "There is nothing at this address."},
    500 => {"Something went wrong", "The error is logged — try again in a moment."}
  }

  def render(template, _assigns) do
    status = template |> String.split(".") |> hd() |> String.to_integer()

    {heading, message} =
      @copy[status] || {Phoenix.Controller.status_message_from_template(template), ""}

    error(%{heading: heading, message: message})
  end

  @doc "Halts a controller with the branded error page for `status`."
  def respond(conn, status, message \\ nil) when status in [403, 404] do
    {heading, default} = @copy[status]

    conn
    |> put_status(status)
    |> put_view(html: __MODULE__)
    |> render(:error, heading: heading, message: message || default)
    |> halt()
  end
end
