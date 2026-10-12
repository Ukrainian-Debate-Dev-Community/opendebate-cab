defmodule CabWeb.RateLimit do
  @moduledoc """
  Rate limits for cab's JSON API (/api/cab/v1). A token bucket per caller:
  a signed-in account has its own bucket, an anonymous caller one per IP.
  A bucket holds `burst` requests and refills at `per_minute`; a request
  takes one token, and an empty bucket answers 429 with Retry-After.
  Every limited response carries RateLimit-Limit, RateLimit-Remaining
  and RateLimit-Reset.

  Settings (`config :cab, CabWeb.RateLimit`): `enabled`, `signed_in` and
  `anonymous` as `{per_minute, burst}`, and `trust_cf_ip`, which reads the
  visitor's address from Cloudflare's CF-Connecting-IP (behind Cloudflare
  and Caddy every request arrives from the proxy's address otherwise).
  Off in development and tests.

  The buckets live in CabWeb.RateLimit.Buckets.
  """
  @behaviour Plug

  import Plug.Conn

  # -- the plug ---------------------------------------------------------

  @impl Plug
  def init(opts), do: opts

  @impl Plug
  def call(conn, _opts) do
    settings = settings()

    if settings[:enabled] do
      {kind, key} = caller(conn, settings)
      {per_minute, burst} = Keyword.fetch!(settings, kind)

      case take({kind, key}, per_minute, burst) do
        {:ok, remaining, reset} ->
          conn |> headers(per_minute, remaining, reset)

        {:error, retry_after} ->
          conn
          |> headers(per_minute, 0, retry_after)
          |> put_resp_header("retry-after", Integer.to_string(retry_after))
          |> put_resp_content_type("application/json")
          |> send_resp(
            429,
            Jason.encode!(%{error: "too many requests", retry_after: retry_after})
          )
          |> halt()
      end
    else
      conn
    end
  end

  defp settings, do: Application.get_env(:cab, __MODULE__, [])

  defp caller(conn, settings) do
    case conn.assigns[:current_user] do
      %{id: id} -> {:signed_in, id}
      _ -> {:anonymous, client_ip(conn, settings)}
    end
  end

  defp client_ip(conn, settings) do
    forwarded = settings[:trust_cf_ip] && List.first(get_req_header(conn, "cf-connecting-ip"))
    forwarded || conn.remote_ip |> :inet.ntoa() |> to_string()
  end

  defp headers(conn, limit, remaining, reset) do
    conn
    |> put_resp_header("ratelimit-limit", Integer.to_string(limit))
    |> put_resp_header("ratelimit-remaining", Integer.to_string(remaining))
    |> put_resp_header("ratelimit-reset", Integer.to_string(reset))
  end

  @doc "Takes one token from the caller's bucket; see CabWeb.RateLimit.Buckets."
  defdelegate take(key, per_minute, burst), to: CabWeb.RateLimit.Buckets

  @doc "Empties every bucket (tests)."
  defdelegate reset(), to: CabWeb.RateLimit.Buckets
end
