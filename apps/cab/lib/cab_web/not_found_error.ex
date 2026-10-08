defmodule CabWeb.NotFoundError do
  @moduledoc "Raised by live pages; renders as a plain 404 on the first render."
  defexception message: "not found", plug_status: 404
end
