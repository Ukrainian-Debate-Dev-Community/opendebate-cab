defmodule Cab.TimeZones do
  @moduledoc """
  Wall-clock times in a named zone (e.g. "Europe/Kyiv") and the UTC
  instants cab stores. Elixir ships no zone database, so Postgres's
  (which knows every IANA zone and its DST rules) does the conversion.
  A form's zone is the one the browser sent with it, else the
  account's, else the deployment's `:default_time_zone`.
  """

  alias Cab.Accounts.User
  alias Cab.Repo

  @utc "Etc/UTC"

  @doc "The deployment's zone for accounts that keep none (`:default_time_zone`)."
  def default, do: Application.get_env(:cab, :default_time_zone) || @utc

  @doc "The zone `user`'s times are typed and shown in on the server."
  def for_user(%User{time_zone: zone}) when is_binary(zone), do: zone
  def for_user(_user), do: default()

  @doc """
  The zone a submitted form's date and time are read in: the form's
  own `zone` (the browser's, put there by app.js) when Postgres knows
  it, else `for_user/1`.
  """
  def for_form(zone, user) do
    if known?(zone), do: zone, else: for_user(user)
  end

  defp known?(zone) when is_binary(zone) and byte_size(zone) in 1..64 do
    %{rows: [[known]]} =
      Repo.query!("SELECT EXISTS (SELECT 1 FROM pg_timezone_names WHERE name = $1)", [zone])

    known
  end

  defp known?(_zone), do: false

  @doc """
  The UTC instant of wall-clock `naive` in `zone`. A time the DST
  change skips reads as one hour later (02:30 -> 03:30 local); a time
  it repeats reads as the later, standard-time one.
  """
  def to_utc(%NaiveDateTime{} = naive, @utc), do: DateTime.from_naive!(naive, @utc)

  def to_utc(%NaiveDateTime{} = naive, zone) do
    %{rows: [[at]]} = Repo.query!("SELECT $1::timestamp AT TIME ZONE $2", [naive, zone])
    DateTime.truncate(at, :second)
  end

  @doc "`at` (UTC) as `zone`'s wall clock: `[\"YYYY-MM-DD\", \"HH:MM\"]`; nil -> `[nil, nil]`."
  def local_parts(nil, _zone), do: [nil, nil]

  def local_parts(%DateTime{} = at, zone) do
    local =
      case zone do
        @utc ->
          DateTime.to_naive(at)

        zone ->
          %{rows: [[local]]} = Repo.query!("SELECT $1::timestamptz AT TIME ZONE $2", [at, zone])
          local
      end

    [Calendar.strftime(local, "%Y-%m-%d"), Calendar.strftime(local, "%H:%M")]
  end
end
