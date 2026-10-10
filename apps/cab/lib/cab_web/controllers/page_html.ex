defmodule CabWeb.PageHTML do
  @moduledoc "The front page (the clubs directory), Policy and Terms."
  use CabWeb, :html

  embed_templates "page_html/*"

  # Policy and Terms keep each sentence whole for translators: links and
  # open placeholders go in as %{bindings}, and the translated sentence
  # (our own catalogue, never user input) is rendered as markup.
  defp sentence(text), do: Phoenix.HTML.raw(text)

  defp mailto(address),
    do: ~s(<a href="mailto:#{address}">#{address}</a>)

  # a detail still to be filled in before launch, marked on the page
  defp todo(text),
    do:
      ~s(<mark class="todo">#{Phoenix.HTML.html_escape(text) |> Phoenix.HTML.safe_to_string()}</mark>)
end
