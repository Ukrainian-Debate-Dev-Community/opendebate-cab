defmodule Public.Geo do
  @moduledoc """
  The club map, from the tenant's `map.json`: the map's size, the
  outline (SVG points), the points of the cities it knows in that size
  and the cities with a branch. Clubs are placed by the city cab gives;
  nothing is stored per club.
  """

  alias Public.Tenant

  @doc "The map's width and height, its SVG viewBox."
  def size do
    [width, height] = Tenant.get([:map, :size])
    {width, height}
  end

  def view_box do
    {width, height} = size()
    "0 0 #{width} #{height}"
  end

  def outline, do: Tenant.get([:map, :outline])

  @doc "The {x, y} point of a city, or nil when the map does not know it."
  def point(nil), do: nil

  def point(city) do
    case Map.get(Tenant.get([:map, :cities]), String.trim(city)) do
      [x, y] -> {x, y}
      _ -> nil
    end
  end

  def branches, do: Enum.map(Tenant.get([:map, :branches]), &{&1, point(&1)})

  @doc """
  A city's name in the page language when the map names it per
  language; any other name is shown as the club wrote it in cab.
  """
  def name(city) do
    case Tenant.get([:map, :names]) do
      %{} = names -> Tenant.translate(names[city]) || city
      _ -> city
    end
  end

  @doc "Where a branch's label sits: :right (the default), :left or :below."
  def label_side(city) do
    case Tenant.get([:map, :label_side]) do
      %{} = sides ->
        case sides[city] do
          "left" -> :left
          "below" -> :below
          _ -> :right
        end

      _ ->
        :right
    end
  end
end
