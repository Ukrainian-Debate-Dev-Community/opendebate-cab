defmodule CabWeb.ClubProfile do
  @moduledoc "Labels for the club profile facts: format, language, audience."
  use Gettext, backend: CabWeb.Gettext

  alias Cab.Clubs.Club

  def format_options, do: Enum.map(Club.formats(), &{format(&1), &1})
  def language_options, do: Enum.map(Club.languages(), &{language(&1), &1})
  def audience_options, do: Enum.map(Club.audiences(), &{audience(&1), &1})

  @doc "A club's formats in words; `other` is the club's own text when it typed one."
  def formats(values, other \\ nil), do: words(values, &format/1, other)
  def languages(values, other \\ nil), do: words(values, &language/1, other)
  def audiences(values), do: words(values, &audience/1, nil)

  defp words([], _label, _other), do: nil

  defp words(values, label, other) do
    values
    |> Enum.map(fn
      "other" when is_binary(other) and other != "" -> other
      value -> label.(value)
    end)
    |> Enum.join(", ")
  end

  defp format("bp"), do: gettext("BP")
  defp format("apf"), do: gettext("APF")
  defp format(_), do: gettext("other format")

  defp language("uk"), do: gettext("Ukrainian")
  defp language("en"), do: gettext("English")
  defp language(_), do: gettext("other language")

  defp audience("school"), do: gettext("school students")
  defp audience("university"), do: gettext("university students")
  defp audience(_), do: gettext("open to all")
end
