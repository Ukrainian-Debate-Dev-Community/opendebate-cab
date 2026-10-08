defmodule CabWeb.ForbiddenError do
  @moduledoc "Raised by live pages; renders as a plain 403 on the first render."
  defexception message: "forbidden", plug_status: 403
end
