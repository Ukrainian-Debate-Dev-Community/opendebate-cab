defmodule CabWeb.SigninHTML do
  @moduledoc """
  /signin: the split page (brand side + "we don't use passwords" card
  with the provider buttons). Google renders disabled ("soon"); the
  guest note covers the personal-link path.
  """

  use CabWeb, :html

  embed_templates "signin_html/*"

  # the sign-in buttons' query: the page to return to, when one asked
  defp return_param(nil), do: []
  defp return_param(back), do: [return_to: back]
end
