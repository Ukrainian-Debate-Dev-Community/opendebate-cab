defmodule CabWeb.GuestLinkHTML do
  @moduledoc "The claim page a personal link shows to a signed-in account."
  use CabWeb, :html

  embed_templates "guest_link_html/*"
end
