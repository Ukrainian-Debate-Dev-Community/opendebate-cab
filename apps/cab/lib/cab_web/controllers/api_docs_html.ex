defmodule CabWeb.ApiDocsHTML do
  @moduledoc "The API reference page."
  use CabWeb, :html

  embed_templates "api_docs_html/*"
end
