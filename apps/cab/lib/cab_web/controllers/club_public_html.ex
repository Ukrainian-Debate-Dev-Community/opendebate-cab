defmodule CabWeb.ClubPublicHTML do
  @moduledoc """
  The club's public pages: the club page (profile + Club Sessions), the
  club standings (teams, speakers, judges) and the join-request form.
  """
  use CabWeb, :html

  import CabWeb.StandingsHTML, only: [standings_tabs: 1, standings_body: 1]

  import CabWeb.FormComponents,
    only: [
      answer_name: 1,
      block_type: 1,
      field_label: 1,
      input_type: 1,
      placeholder: 1,
      prompt: 1
    ]

  embed_templates "club_public_html/*"

  # list_members/1 orders head first
  defp head_name([%{user: user} | _rest]), do: user.name || user.username
  defp head_name([]), do: nil
end
