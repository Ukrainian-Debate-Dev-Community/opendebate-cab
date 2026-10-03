defmodule CabWeb.Api.FallbackController do
  @moduledoc """
  Turns context error tuples into JSON error responses so the API
  controllers stay one happy-path function each.
  """

  use CabWeb, :controller

  def call(conn, {:error, %Ecto.Changeset{} = changeset}) do
    errors =
      Ecto.Changeset.traverse_errors(changeset, fn {message, opts} ->
        Regex.replace(~r"%{(\w+)}", message, fn _, key ->
          opts |> Keyword.get(String.to_existing_atom(key), key) |> to_string()
        end)
      end)

    conn |> put_status(422) |> json(%{error: "validation failed", details: errors})
  end

  def call(conn, {:error, message}) when is_binary(message) do
    conn |> put_status(422) |> json(%{error: message})
  end
end
