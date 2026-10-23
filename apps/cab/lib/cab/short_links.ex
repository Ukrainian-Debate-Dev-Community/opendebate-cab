defmodule Cab.ShortLinks do
  @moduledoc """
  Short links, `<cab host>/<code>`, for any long link people copy or
  print. A link points at one target:

    * a cab path - `"/c/<club>/standings/teams"`
    * an absolute URL on an allowed host - `config :cab,
      :short_link_hosts, ["example.org"]` (`SHORT_LINK_HOSTS` in
      production); a URL on cab's own host is kept as its path
    * a session - resolved when opened, so the link follows the
      session (`/<code>/<n>` opens its room n)

  Codes come from `Core.ShortCode`. Asking twice for the same target
  gives the same link. Personal links (`/l/...`) and invitations are
  credentials and stay long - never shorten them.
  """

  import Ecto.Query

  alias Cab.Repo
  alias Cab.Sessions.Session
  alias Cab.ShortLinks.ShortLink

  @tries 5

  @doc """
  The target's short link, e.g. `https://cab.example.org/k7m2q9`; for a
  session, `room_no` appends the room. Raises `ArgumentError` for a
  target that may not be shortened (see `link/1`).
  """
  def short_url(target, room_no \\ nil)

  def short_url(%Session{} = session, room_no) do
    base = url_for(session)
    if room_no, do: "#{base}/#{room_no}", else: base
  end

  def short_url(target, nil), do: url_for(target)

  defp url_for(target) do
    case link(target) do
      {:ok, link} -> CabWeb.Endpoint.url() <> "/" <> link.code
      {:error, :invalid_target} -> raise ArgumentError, "cannot shorten #{inspect(target)}"
    end
  end

  @doc """
  The target's link row, created the first time: `{:ok, link}` or
  `{:error, :invalid_target}` (not a cab path, a URL off the allowed
  hosts, or anything else).
  """
  def link(target) do
    case normalize(target) do
      {:ok, field, value} -> find(field, value) || create(field, value, @tries)
      :error -> {:error, :invalid_target}
    end
  end

  @doc """
  What a code opens: `{:path, path}`, `{:url, url}`, `{:session,
  session}` (club preloaded), or nil for anything that is not a live
  code.
  """
  def resolve(code) do
    with true <- Core.ShortCode.code?(code),
         %ShortLink{} = link <- Repo.get_by(ShortLink, code: code) do
      case link do
        %ShortLink{session_id: id} when is_integer(id) ->
          {:session, Repo.one(from s in Session, where: s.id == ^id, preload: :club)}

        # the host is checked again: one dropped from the allowed
        # hosts no longer opens
        %ShortLink{url: url} when is_binary(url) ->
          if match?({:ok, :url, _url}, normalize(url)), do: {:url, url}

        %ShortLink{path: path} ->
          {:path, path}
      end
    else
      _ -> nil
    end
  end

  # {:ok, field, value} | :error
  defp normalize(%Session{id: id}) when is_integer(id), do: {:ok, :session_id, id}

  defp normalize("/" <> _ = path) do
    if local_path?(path), do: {:ok, :path, path}, else: :error
  end

  defp normalize(url) when is_binary(url) do
    with %URI{scheme: scheme, host: host, userinfo: nil} = uri when scheme in ["http", "https"] <-
           URI.parse(url),
         true <- is_binary(host) and host != "" do
      host = String.downcase(host)

      cond do
        host == own_host() -> normalize(local_part(uri))
        host in allowed_hosts() -> {:ok, :url, URI.to_string(%{uri | host: host})}
        true -> :error
      end
    else
      _ -> :error
    end
  end

  defp normalize(_target), do: :error

  # a path on this host: never "//host" (protocol-relative) or a backslash
  defp local_path?(path) do
    not String.starts_with?(path, "//") and not String.contains?(path, "\\") and
      String.valid?(path) and not (path =~ ~r/[\s\x00-\x1f]/)
  end

  defp local_part(%URI{path: path, query: query, fragment: fragment}) do
    (path || "/") <>
      if(query, do: "?" <> query, else: "") <>
      if(fragment, do: "#" <> fragment, else: "")
  end

  defp own_host, do: String.downcase(CabWeb.Endpoint.host())

  defp allowed_hosts do
    :cab
    |> Application.get_env(:short_link_hosts, [])
    |> Enum.map(&String.downcase/1)
  end

  defp find(field, value) do
    case Repo.one(from l in ShortLink, where: field(l, ^field) == ^value) do
      nil -> nil
      link -> {:ok, link}
    end
  end

  # a fresh code; on a code clash try another, and when someone else
  # created the same target meanwhile, theirs is the link
  defp create(field, value, tries) do
    changeset =
      ShortLink.changeset(struct(ShortLink, [{field, value}, code: Core.ShortCode.generate()]))

    case Repo.insert(changeset) do
      {:ok, link} ->
        {:ok, link}

      {:error, %Ecto.Changeset{errors: errors}} ->
        cond do
          Keyword.has_key?(errors, :code) and tries > 1 -> create(field, value, tries - 1)
          found = find(field, value) -> found
          true -> {:error, :invalid_target}
        end
    end
  end
end
