defmodule Core.Engine do
  @moduledoc """
  HTTP client for the Node tab engine.

  The engine trusts HS256 JWTs signed with a shared secret
  (`ENGINE_JWT_SECRET`), payload `{id, isAdmin}` - compatible with the
  Node `jsonwebtoken` verify on the other side. The gateway mints
  short-lived tokens per request instead of storing engine sessions.
  """

  require Logger

  @token_ttl_seconds 300
  @provision_attempts 3

  @doc """
  Mints a short-lived HS256 JWT the engine accepts as authentication
  for the engine user `node_user_id`.
  """
  def mint_token(node_user_id, is_admin \\ false) do
    now = System.os_time(:second)

    claims = %{
      "id" => node_user_id,
      "isAdmin" => is_admin,
      "iat" => now,
      "exp" => now + @token_ttl_seconds
    }

    Joken.generate_and_sign!(%{}, claims, signer())
  end

  @doc """
  Creates an engine user for `username` via `POST /api/users/register`
  with a random strong password (OAuth users never learn it; the JWT
  shared secret is the real credential).

  Returns `{:ok, engine_user_id}` parsed from the `id` claim of the
  token in the register response. On a username conflict retries with
  a random suffix a few times.
  """
  def provision_user(username), do: provision_user(username, username, @provision_attempts)

  defp provision_user(_username, _candidate, 0), do: {:error, :username_conflict}

  defp provision_user(username, candidate, attempts) do
    password = :crypto.strong_rand_bytes(24) |> Base.url_encode64(padding: false)

    case guarded(&Req.post/2, base_req(),
           url: "/api/users/register",
           json: %{username: candidate, password: password}
         ) do
      {:ok, %Req.Response{status: status, body: %{"token" => token}}} when status in 200..299 ->
        id_from_token(token)

      {:ok, %Req.Response{status: status}} when status in [400, 409] ->
        suffix = :crypto.strong_rand_bytes(2) |> Base.encode16(case: :lower)
        provision_user(username, "#{username}-#{suffix}", attempts - 1)

      {:ok, %Req.Response{status: status}} ->
        {:error, {:unexpected_status, status}}

      {:error, exception} ->
        {:error, exception}
    end
  end

  @doc """
  GET on the engine as `node_user_id` (Bearer of a freshly minted token).

  Pass `admin: true` in `opts` to mint the token with the `isAdmin`
  claim set (the engine trusts the claim as-is).
  """
  def get(node_user_id, path, opts \\ []) do
    {admin, opts} = Keyword.pop(opts, :admin, false)
    guarded(&Req.get/2, authed_req(node_user_id, admin), Keyword.put(opts, :url, path))
  end

  @doc """
  POST a JSON body to the engine as `node_user_id`.
  """
  def post(node_user_id, path, body, opts \\ []) do
    request(:post, node_user_id, path, body, opts)
  end

  @doc """
  PUT a JSON body to the engine as `node_user_id`.
  """
  def put(node_user_id, path, body, opts \\ []) do
    request(:put, node_user_id, path, body, opts)
  end

  @doc """
  PATCH a JSON body to the engine as `node_user_id`.
  """
  def patch(node_user_id, path, body, opts \\ []) do
    request(:patch, node_user_id, path, body, opts)
  end

  @doc """
  DELETE on the engine as `node_user_id`.
  """
  def delete(node_user_id, path, opts \\ []) do
    {admin, opts} = Keyword.pop(opts, :admin, false)
    guarded(&Req.delete/2, authed_req(node_user_id, admin), Keyword.put(opts, :url, path))
  end

  # a burst can drain the HTTP pool to the engine; that is an engine
  # error the caller reports in words, never a crash
  defp guarded(call, request, opts) do
    call.(request, opts)
  rescue
    error in RuntimeError ->
      if String.contains?(error.message, "unable to provide a connection"),
        do: {:error, %RuntimeError{message: "the engine is busy, try again in a moment"}},
        else: reraise(error, __STACKTRACE__)
  end

  defp request(method, node_user_id, path, body, opts) do
    {admin, opts} = Keyword.pop(opts, :admin, false)

    guarded(
      &Req.request/2,
      authed_req(node_user_id, admin),
      opts
      |> Keyword.put(:method, method)
      |> Keyword.put(:url, path)
      |> Keyword.put(:json, body)
    )
  end

  @doc """
  GET on an engine endpoint that requires no authentication
  (e.g. the public `GET /api/events`).
  """
  def public_get(path, opts \\ []) do
    guarded(&Req.get/2, base_req(), Keyword.put(opts, :url, path))
  end

  defp id_from_token(token) do
    case Joken.verify(token, signer()) do
      {:ok, %{"id" => id}} -> {:ok, id}
      {:ok, _claims} -> {:error, :missing_id_claim}
      {:error, reason} -> {:error, reason}
    end
  end

  defp authed_req(node_user_id, is_admin) do
    Req.merge(base_req(), auth: {:bearer, mint_token(node_user_id, is_admin)})
  end

  defp base_req do
    config = config()

    Req.new(
      base_url: Keyword.get(config, :base_url, "http://localhost:3100"),
      retry: false
    )
    # test env injects [plug: {Req.Test, Core.Engine}] here to stub the engine
    |> Req.merge(Keyword.get(config, :req_options, []))
    |> Req.Request.prepend_request_steps(engine_clock: &start_clock/1)
    |> Req.Request.append_response_steps(engine_log: &log_call/1)
  end

  # one debug line per engine call ("engine GET /api/... 200 12ms") -
  # visible in dev, silent at the production log level
  defp start_clock(request),
    do: Req.Request.put_private(request, :engine_started, System.monotonic_time())

  defp log_call({request, response}) do
    started = Req.Request.get_private(request, :engine_started, System.monotonic_time())
    ms = System.convert_time_unit(System.monotonic_time() - started, :native, :millisecond)

    Logger.debug(fn ->
      "engine #{String.upcase(to_string(request.method))} #{request.url.path} #{response.status} #{ms}ms"
    end)

    {request, response}
  end

  defp signer do
    Joken.Signer.create("HS256", Keyword.fetch!(config(), :jwt_secret))
  end

  defp config, do: Application.get_env(:core, __MODULE__, [])
end
