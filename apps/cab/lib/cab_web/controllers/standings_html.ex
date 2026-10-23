defmodule CabWeb.StandingsHTML do
  @moduledoc """
  The global standings page and the two components the club standings
  reuse: the tab row and one tab's content.
  """
  use CabWeb, :html

  embed_templates "standings_html/*"

  @doc """
  The standings tabs (`.selrow`), shared by both scopes -
  the Clubs tab is GLOBAL-ONLY (a club comparing clubs inside its
  own scope makes no sense).
  """
  attr :base, :string, required: true
  attr :active, :string, required: true
  attr :clubs_tab, :boolean, default: true

  def standings_tabs(assigns)

  @doc """
  One standings tab's content - RULE 0: the engine's output verbatim
  for ONE session (teams, speakers, judge stats), clubs as plain
  counts. With `archive` and `base` the scope card links the earlier
  sessions (club scope); nil = global.
  """
  attr :tab, :string, required: true
  attr :scope, :any, default: nil, doc: "%{session, club, actor} or nil (none finished)"
  attr :rows, :list, required: true
  attr :club, :any, default: nil
  attr :archive, :list, default: nil
  attr :base, :string, default: nil

  def standings_body(assigns)

  # the stepper's link `offset` sessions from the shown one in the
  # archive (newest first: +1 is earlier, -1 later), nil past either end
  defp step_href(%{archive: archive, scope: scope, base: base, tab: tab}, offset) do
    index = Enum.find_index(archive, &(&1.session_uuid == scope.session.uuid))
    to = index && index + offset

    case to && to >= 0 && Enum.at(archive, to) do
      %{session_uuid: uuid} -> "#{base}/#{tab}?session=#{uuid}"
      _ -> nil
    end
  end

  defp scope_date(%{session: session}), do: session.scheduled_at || session.inserted_at

  defp tab_label("teams"), do: gettext("Teams")
  defp tab_label("speakers"), do: gettext("Speakers")
  defp tab_label("adjudicators"), do: gettext("Adjudicators")
  defp tab_label("clubs"), do: gettext("Clubs")
end
