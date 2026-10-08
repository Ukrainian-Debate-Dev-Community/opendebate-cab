defmodule CabWeb.SessionPageHTML do
  @moduledoc """
  The session page, the room page (both rendered by LiveViews) and the
  ballot page. One room URL for every viewer: identity picks what
  renders and which actions appear.
  """
  use CabWeb, :html

  # this module's ballot/1 is the ballot PAGE; the kit's ballot
  # component stays qualified as Ui.ballot
  import CabWeb.Ui, except: [ballot: 1]
  alias CabWeb.Ui

  embed_templates "session_page_html/*"

  # the prep clock: 15 minutes from the motion's publication — the
  # engine ships created_at (ISO) with the motion; absent = no clock
  defp prep_deadline(room) do
    with %{"created_at" => created} when is_binary(created) <- room["Motion"],
         {:ok, at, _offset} <- DateTime.from_iso8601(created) do
      at |> DateTime.add(15, :minute) |> DateTime.to_iso8601()
    else
      _ -> nil
    end
  end

  defp my_room_motion(%{rooms: rooms}, my_room_id) when is_integer(my_room_id) do
    case Enum.find(rooms, &(&1["id"] == my_room_id)) do
      %{"Motion" => %{"motion_text" => motion}} when is_binary(motion) -> motion
      _ -> nil
    end
  end

  defp my_room_motion(_state, _my_room_id), do: nil
end
