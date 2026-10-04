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

  def call(conn, {:error, :forbidden}) do
    conn |> put_status(403) |> json(%{error: "forbidden"})
  end

  # lifecycle gates (signups while :signup, composition while :closed)
  def call(conn, {:error, :conflict, message}) do
    conn |> put_status(409) |> json(%{error: message})
  end

  # changeset-style error maps built by the contexts (field => message)
  def call(conn, {:error, %{} = details}) when not is_struct(details) do
    conn |> put_status(422) |> json(%{error: "validation failed", details: details})
  end

  def call(conn, {:error, message}) when is_binary(message) do
    conn |> put_status(422) |> json(%{error: message})
  end
end
