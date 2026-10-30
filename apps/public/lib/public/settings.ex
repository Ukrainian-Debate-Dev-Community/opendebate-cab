defmodule Public.Settings do
  @moduledoc """
  Site-wide switches that only cab admins flip. The calendar is public
  unless an admin turns it off; then no event reaches a public page or
  the iCal feed, while content managers keep working on it.
  """
  alias Public.Repo
  alias Public.Settings.Setting

  @calendar "calendar_public"

  def calendar_public? do
    case Repo.get_by(Setting, key: @calendar) do
      %Setting{value: "false"} -> false
      _ -> true
    end
  end

  def set_calendar_public(public?, user_id) when is_boolean(public?) do
    now = DateTime.utc_now(:second)

    Repo.insert(
      %Setting{
        key: @calendar,
        value: to_string(public?),
        updated_by_user_id: user_id,
        inserted_at: now,
        updated_at: now
      },
      on_conflict: [
        set: [value: to_string(public?), updated_by_user_id: user_id, updated_at: now]
      ],
      conflict_target: :key
    )
  end
end
