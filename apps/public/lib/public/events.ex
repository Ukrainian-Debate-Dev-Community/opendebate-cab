defmodule Public.Events do
  @moduledoc """
  The calendar: tournaments first, plus trainings and club events.
  Public functions return public events only, and none at all while an
  admin keeps the whole calendar private; the `_all` variants are for
  /manage, where private events live.
  """
  import Ecto.Query

  alias Public.Events.Event
  alias Public.{Repo, Settings, Tags}

  # `range` is `{first, last}`, the dates to cover, or nil for every event
  def public_in(range, kind \\ nil) do
    if Settings.calendar_public?(),
      do: in_range(from(e in Event, where: e.visibility == "public"), range, kind),
      else: []
  end

  def all_in(range, kind \\ nil, tag \\ nil) do
    Event
    |> Tags.only(tag, {"event_tags", :event_id})
    |> preload(:tags)
    |> in_range(range, kind)
  end

  def upcoming_public(%Date{} = today, limit \\ 5) do
    if Settings.calendar_public?(), do: upcoming_public!(today, limit), else: []
  end

  defp upcoming_public!(today, limit) do
    Repo.all(
      from e in Event,
        where: e.visibility == "public" and coalesce(e.ends_on, e.starts_on) >= ^today,
        order_by: [asc: e.starts_on],
        limit: ^limit
    )
  end

  def upcoming_all(%Date{} = today) do
    Repo.all(
      from e in Event,
        where: coalesce(e.ends_on, e.starts_on) >= ^today,
        order_by: [asc: e.starts_on],
        preload: :tags
    )
  end

  def all_public do
    if Settings.calendar_public?(),
      do: Repo.all(from e in Event, where: e.visibility == "public", order_by: e.starts_on),
      else: []
  end

  # one public event, or nil: private, missing, or the calendar private
  def get_public(id) do
    with true <- Settings.calendar_public?(),
         {id, ""} when id in 1..9_223_372_036_854_775_807 <- Integer.parse(to_string(id)) do
      Repo.get_by(Event, id: id, visibility: "public")
    else
      _ -> nil
    end
  end

  def get!(id), do: Event |> Repo.get!(id) |> Repo.preload(:tags)

  def change(event \\ %Event{}, attrs \\ %{}), do: Event.changeset(event, attrs)

  def create(attrs, user_id) do
    %Event{created_by_user_id: user_id}
    |> Event.changeset(attrs)
    |> Tags.put(attrs)
    |> Repo.insert()
  end

  def update(%Event{} = event, attrs),
    do: event |> Event.changeset(attrs) |> Tags.put(attrs) |> Repo.update()

  def set_visibility(%Event{} = event, visibility) when visibility in ~w(public private),
    do: event |> Ecto.Changeset.change(visibility: visibility) |> Repo.update()

  def delete(%Event{} = event), do: Repo.delete(event)

  defp in_range(query, range, kind) do
    from(e in query, order_by: [asc: e.starts_on])
    |> between(range)
    |> by_kind(kind)
    |> Repo.all()
  end

  defp between(query, nil), do: query

  defp between(query, {first, last}),
    do:
      from(e in query, where: e.starts_on <= ^last and coalesce(e.ends_on, e.starts_on) >= ^first)

  defp by_kind(query, kind) when kind in [nil, ""], do: query
  defp by_kind(query, kind), do: from(e in query, where: e.kind == ^kind)
end
