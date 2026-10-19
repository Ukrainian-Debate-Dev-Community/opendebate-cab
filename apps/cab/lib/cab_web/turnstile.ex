defmodule CabWeb.Turnstile do
  @moduledoc """
  Cloudflare Turnstile, the challenge on cab's public forms. Off unless
  both keys are set (`config :cab, :turnstile, site_key: ...,
  secret_key: ...`; runtime.exs reads TURNSTILE_SITE_KEY and
  TURNSTILE_SECRET_KEY in production). When on, the form renders the
  widget and every submit is checked with Cloudflare's siteverify
  before anything is created. Cloudflare out of reach refuses the
  submit (fail closed). `req_options` lets tests stub the call.

  Cloudflare's test keys: site key `1x00000000000000000000AA` (always
  passes), secrets `1x0000000000000000000000000000000AA` (always
  passes) and `2x0000000000000000000000000000000AA` (always fails).
  """

  @verify_url "https://challenges.cloudflare.com/turnstile/v0/siteverify"

  @doc "The token field the widget adds to its form."
  def response_field, do: "cf-turnstile-response"

  @doc "The site key when Turnstile is on, nil when it is off."
  def site_key do
    settings = settings()

    if present?(settings[:site_key]) and present?(settings[:secret_key]),
      do: settings[:site_key]
  end

  @doc "Is Turnstile on?"
  def enabled?, do: site_key() != nil

  @doc """
  Checks a widget token with Cloudflare: `:ok`, `{:error, :failed}`
  (no token, or Cloudflare says no) or `{:error, :unavailable}`
  (Cloudflare out of reach or failing). `:ok` when Turnstile is off.
  """
  def verify(token, remote_ip) do
    cond do
      not enabled?() -> :ok
      not present?(token) -> {:error, :failed}
      true -> siteverify(token, remote_ip)
    end
  end

  defp siteverify(token, remote_ip) do
    settings = settings()

    form =
      [secret: settings[:secret_key], response: token, remoteip: remote_ip]
      |> Enum.reject(fn {_key, value} -> is_nil(value) end)

    options =
      [url: @verify_url, form: form, retry: false, receive_timeout: 5_000]
      |> Keyword.merge(settings[:req_options] || [])

    case Req.post(options) do
      {:ok, %{status: 200, body: %{"success" => true}}} ->
        :ok

      {:ok, %{status: 200, body: %{"success" => false} = body}} ->
        if "internal-error" in List.wrap(body["error-codes"]),
          do: {:error, :unavailable},
          else: {:error, :failed}

      _other ->
        {:error, :unavailable}
    end
  end

  defp settings, do: Application.get_env(:cab, :turnstile, [])

  defp present?(value), do: is_binary(value) and String.trim(value) != ""
end
