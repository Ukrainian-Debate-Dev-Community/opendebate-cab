defmodule CabWeb.MemberHTML do
  @moduledoc "The member roster and the shared Club Sessions table."
  use CabWeb, :html

  embed_templates "member_html/*"

  @doc "The Club Sessions table — every session with its status in words; shared by the club and owner pages."
  attr :club, :any, required: true
  attr :archive, :list, required: true

  def archive_section(assigns)

  # a membership role in words
  defp role_word("head"), do: gettext("head")
  defp role_word("member"), do: gettext("member")
  defp role_word(role), do: role
end
