defmodule CabWeb.MeHTML do
  @moduledoc "/me - profile, invitations, my clubs and schedule, engine stats verbatim, history."
  use CabWeb, :html

  embed_templates "me_html/*"

  # the Next session column, written out as words - no pills anywhere
  defp tonight_words(nil), do: gettext("quiet")

  defp tonight_words({_session, :signup, _rooms}), do: gettext("registration open")

  defp tonight_words({_session, :closed, _rooms}), do: gettext("registration closed")

  defp tonight_words({_session, :running, _rooms}), do: gettext("running")

  # a role as people read it: club roles and session roles
  defp role_word("head"), do: gettext("head")
  defp role_word("member"), do: gettext("member")
  defp role_word("speaker"), do: gettext("speaker")
  defp role_word("adjudicator"), do: gettext("adjudicator")
  defp role_word(other), do: other
end
