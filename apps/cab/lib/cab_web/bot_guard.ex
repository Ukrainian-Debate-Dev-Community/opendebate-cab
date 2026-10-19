defmodule CabWeb.BotGuard do
  @moduledoc """
  Bot protection for cab's public forms (a guest's registration at
  /r/:session_uuid, a join request at /c/:club_uuid/join): the form
  renders `<.form_for guard>`, its action calls `check/3` before
  creating anything.

    * Turnstile (CabWeb.Turnstile), when configured: the widget on the
      form, its token checked with Cloudflare on submit.
  """
  use Gettext, backend: CabWeb.Gettext

  @doc """
  Checks a submit of a guarded form: `:ok`, or `{:error, message}`
  for the form's `:turnstile` error.
  """
  def check(conn, params, _form) do
    case CabWeb.Turnstile.verify(
           params[CabWeb.Turnstile.response_field()],
           CabWeb.RateLimit.client_ip(conn)
         ) do
      :ok ->
        :ok

      {:error, :failed} ->
        {:error, gettext("Please confirm you are not a robot.")}

      {:error, :unavailable} ->
        {:error,
         gettext("We could not check that you are not a robot right now. Please try again.")}
    end
  end
end
