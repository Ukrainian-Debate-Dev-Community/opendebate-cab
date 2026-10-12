defmodule CabWeb.AdminHTML do
  @moduledoc "/admin - clubs table, create a club, change a head."
  use CabWeb, :html

  embed_templates "admin_html/*"

  defp head_label(nil), do: "—"
  defp head_label(user), do: user.name || user.username

  defp club_options(clubs), do: Enum.map(clubs, &{&1.name, &1.uuid})

  defp day(%DateTime{} = at), do: Calendar.strftime(at, "%Y-%m-%d")
end
