defmodule Public.Tags do
  @moduledoc """
  Private labels (a status, a stage) that content managers put on events
  and news. They exist only under /manage: no public page, feed or
  query ever loads them.
  """
  import Ecto.Query

  alias Public.Repo
  alias Public.Tags.Tag

  def list, do: Repo.all(from t in Tag, order_by: [asc: t.name])

  def get!(id), do: Repo.get!(Tag, id)

  @doc "The tag a ?tag= filter names, or nil for anything else."
  def find(id) do
    case parse_id(id) do
      nil -> nil
      id -> Repo.get(Tag, id)
    end
  end

  @doc "The tags with these ids (strings from a form, blanks ignored)."
  def by_ids(ids) do
    ids = ids |> List.wrap() |> Enum.map(&parse_id/1) |> Enum.reject(&is_nil/1)
    Repo.all(from t in Tag, where: t.id in ^ids, order_by: [asc: t.name])
  end

  @doc """
  Puts the tags a form sent as tag_ids on an event's or a post's
  changeset; a form without the field leaves the tags as they are.
  """
  def put(changeset, %{"tag_ids" => ids}),
    do: Ecto.Changeset.put_assoc(changeset, :tags, by_ids(ids))

  def put(changeset, _attrs), do: changeset

  @doc "Only the rows carrying the tag, in a query over events or news posts."
  def only(query, nil, _join), do: query

  def only(query, %Tag{id: id}, {table, key}) do
    from r in query,
      where:
        r.id in subquery(
          from j in table, where: j.tag_id == ^id, select: type(field(j, ^key), :integer)
        )
  end

  def change(tag \\ %Tag{}, attrs \\ %{}), do: Tag.changeset(tag, attrs)

  def create(attrs), do: %Tag{} |> Tag.changeset(attrs) |> Repo.insert()

  def update(%Tag{} = tag, attrs), do: tag |> Tag.changeset(attrs) |> Repo.update()

  def delete(%Tag{} = tag), do: Repo.delete(tag)

  defp parse_id(id) when is_integer(id), do: id

  defp parse_id(id) when is_binary(id) do
    case Integer.parse(id) do
      {n, ""} -> n
      _ -> nil
    end
  end

  defp parse_id(_), do: nil
end
