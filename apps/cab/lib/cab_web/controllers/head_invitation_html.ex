defmodule CabWeb.HeadInvitationHTML do
  @moduledoc "The page for a head invitation link that no longer works."
  use CabWeb, :html

  embed_templates "head_invitation_html/*"

  defp reason_words(:expired), do: gettext("This invitation has expired.")
  defp reason_words(:used), do: gettext("This invitation was already accepted.")
  defp reason_words(:cancelled), do: gettext("This invitation was cancelled.")
  defp reason_words(_unknown), do: gettext("This invitation link is not valid.")
end
