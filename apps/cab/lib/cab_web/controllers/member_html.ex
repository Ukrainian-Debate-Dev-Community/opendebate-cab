defmodule CabWeb.MemberHTML do
  @moduledoc "The member roster and the shared Club Sessions table."
  use CabWeb, :html

  embed_templates "member_html/*"

  @doc """
  The Club Sessions table - every session: name, date and time,
  status in words, and the viewer's action (Register / Cancel
  registration while it takes sign-ups, else Open); shared by the
  club and owner pages.
  """
  attr :club, :any, required: true
  attr :archive, :list, required: true

  attr :mine, :map,
    default: %{},
    doc: "session uuid => the viewer's participant id (open sessions)"

  attr :owner, :boolean,
    default: false,
    doc: "the head's edit view: every row opens the owner tree"

  def archive_section(assigns)

  # a membership role in words
  defp role_word("head"), do: gettext("head")
  defp role_word("member"), do: gettext("member")
  defp role_word(role), do: role
end
