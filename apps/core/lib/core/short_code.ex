defmodule Core.ShortCode do
  @moduledoc """
  Short link codes: six characters from an alphabet without look-alikes
  (no 0/o, 1/l/i), always holding a digit, so a code never spells a
  page address (`/signin`, `/admin`) and reads back unambiguously from
  a printed card. Pure - storage and resolution belong to the app that
  serves the links.

      iex> Core.ShortCode.code?(Core.ShortCode.generate())
      true
      iex> Core.ShortCode.code?("signin")
      false
  """

  @alphabet ~c"abcdefghjkmnpqrstuvwxyz23456789"
  @digits ~c"23456789"

  @doc "A fresh random code."
  def generate do
    code = for _ <- 1..6, into: "", do: <<Enum.random(@alphabet)>>

    if String.contains?(code, Enum.map(@digits, &<<&1>>)),
      do: code,
      else: generate()
  end

  @doc "Whether a path segment can be a code at all."
  def code?(segment) when is_binary(segment) do
    String.match?(segment, ~r/^[a-hjkmnp-z2-9]{6}$/) and String.match?(segment, ~r/[2-9]/)
  end

  def code?(_segment), do: false
end
