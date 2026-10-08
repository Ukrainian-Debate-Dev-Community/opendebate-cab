defmodule CabWeb.MeHTML do
  @moduledoc "/me — profile line, engine stats verbatim, participation history."
  use CabWeb, :html

  embed_templates "me_html/*"
end
