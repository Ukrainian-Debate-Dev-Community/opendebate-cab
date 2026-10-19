defmodule CabWeb.BotGuard do
  @moduledoc """
  Bot protection for cab's public forms (a guest's registration at
  /r/:session_uuid, a join request at /c/:club_uuid/join): the form
  renders `<.form_for guard>`, its action calls `check/3` before
  creating anything.

    * a rate limit per form (opt-in): token buckets (CabWeb.RateLimit.Buckets)
      per client IP and per session for a guest's registration, per
      account and per IP for join requests. Over a limit the form
      answers 429 with Retry-After and nothing is created.
    * Turnstile (CabWeb.Turnstile), when configured: the widget on the
      form, its token checked with Cloudflare on submit.

  Settings (`config :cab, CabWeb.BotGuard`): `rate_limit` (off unless
  an operator turns it on) and each limit as `{count, seconds}`:
  `guest_per_ip`, `guest_per_session`, `join_per_user`, `join_per_ip`.
  A bucket holds `count` submits and refills over `seconds`.
  """
  use Gettext, backend: CabWeb.Gettext

  import Plug.Conn

  @doc """
  Checks a submit of a guarded form - `{:guest, session}` or `{:join,
  club, user}`: `:ok`, `{:limited, seconds}` (see `limited/2`) or
  `{:error, message}` for the form's `:turnstile` error.
  """
  def check(conn, params, form) do
    with :ok <- throttle(conn, form) do
      turnstile(conn, params)
    end
  end

  @doc """
  An over-the-limit answer: status 429, Retry-After and a flash; the
  caller renders the form again.
  """
  def limited(conn, seconds) do
    minutes = max(1, ceil(seconds / 60))

    conn
    |> put_status(429)
    |> put_resp_header("retry-after", Integer.to_string(seconds))
    |> Phoenix.Controller.put_flash(
      :error,
      ngettext(
        "Too many attempts. Please try again in %{count} minute.",
        "Too many attempts. Please try again in %{count} minutes.",
        minutes
      )
    )
  end

  # every bucket of the form takes a token; the first empty one answers
  defp throttle(conn, form) do
    settings = Application.get_env(:cab, __MODULE__, [])

    if settings[:rate_limit] do
      ip = CabWeb.RateLimit.client_ip(conn)

      form
      |> buckets(ip)
      |> Enum.reduce_while(:ok, fn {name, key}, :ok ->
        {count, seconds} = Keyword.fetch!(settings, name)

        case CabWeb.RateLimit.take({__MODULE__, name, key}, count * 60 / seconds, count) do
          {:ok, _remaining, _reset} -> {:cont, :ok}
          {:error, retry_after} -> {:halt, {:limited, retry_after}}
        end
      end)
    else
      :ok
    end
  end

  defp buckets({:guest, session}, ip), do: [guest_per_ip: ip, guest_per_session: session.id]
  defp buckets({:join, _club, user}, ip), do: [join_per_user: user.id, join_per_ip: ip]

  defp turnstile(conn, params) do
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
