defmodule PublicWeb.Clubs do
  @moduledoc """
  Clubs as cab keeps them, read downward: every club that is not
  archived, with its public profile (name, city, meeting time, contacts,
  format, language, audience and logo). the site stores nothing
  about a club.
  """

  def list, do: Cab.Clubs.list_clubs()

  def get(uuid) do
    case Ecto.UUID.cast(uuid) do
      {:ok, uuid} ->
        case Cab.Clubs.get_by_uuid(uuid) do
          %{archived_at: nil} = club -> club
          _ -> nil
        end

      :error ->
        nil
    end
  end

  @doc "The club's logo as cab serves it (its API's logo_url), nil without one."
  def logo_url(club), do: CabWeb.ClubProfile.logo_url(club)

  def city_counts(clubs) do
    clubs
    |> Enum.map(&(&1.city && String.trim(&1.city)))
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.frequencies()
  end

  def member_count(club), do: Map.get(Cab.Clubs.member_counts([club.id]), club.id, 0)

  def head_name(club) do
    case Enum.find(Cab.Clubs.list_members(club), &(&1.role == "head")) do
      nil -> nil
      m -> m.user.name || m.user.username
    end
  end

  def filter(clubs, params) do
    Enum.filter(clubs, fn club ->
      city_is?(club.city, params["city"]) and has?(club.formats, params["format"]) and
        has?(club.languages, params["language"]) and has?(club.audiences, params["audience"])
    end)
  end

  defp city_is?(_city, blank) when blank in [nil, ""], do: true
  defp city_is?(city, wanted), do: city != nil and String.trim(city) == wanted

  defp has?(_values, blank) when blank in [nil, ""], do: true
  defp has?(values, wanted), do: wanted in (values || [])
end
