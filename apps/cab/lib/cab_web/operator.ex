defmodule CabWeb.Operator do
  @moduledoc """
  Who runs this cab: the name, links and addresses shown in the footer,
  on the sign-in page and on the account page. Set
  `config :cab, :operator, SomeModule`, a module whose `info/0` returns a
  map with any of these keys, already translated:

    * `:about` - the footer's "Find your club" text
    * `:site_url` - the main site ("Main page" link)
    * `:org_text`, `:org_label`, `:org_url` - the "Our organisation" column
    * `:contact_email` - "Contact us"
    * `:support_email` - "Support" and the account page's data requests
    * `:signin_foot` - the line under the sign-in features

  Without it cab shows none of them.
  """

  @callback info() :: map()

  def get(key), do: Map.get(info(), key)

  defp info do
    case Application.get_env(:cab, :operator) do
      nil -> %{}
      module -> module.info()
    end
  end
end
