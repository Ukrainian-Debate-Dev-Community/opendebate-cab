defmodule PublicWeb.NotFound do
  @moduledoc "Raised for anything a visitor may not see: always a plain 404."
  defexception message: "not found", plug_status: 404
end
