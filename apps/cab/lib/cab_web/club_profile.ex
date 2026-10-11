defmodule CabWeb.ClubProfile do
  @moduledoc "Labels for the club profile facts: format, language, audience."
  use Gettext, backend: CabWeb.Gettext

  alias Cab.Clubs.Club

  def format_options, do: Enum.map(Club.formats(), &{format(&1), &1})
  def language_options, do: Enum.map(Club.languages(), &{language(&1), &1})
  def audience_options, do: Enum.map(Club.audiences(), &{audience(&1), &1})

  def formats(values), do: words(values, &format/1)
  def languages(values), do: words(values, &language/1)
  def audiences(values), do: words(values, &audience/1)

  defp words([], _label), do: nil
  defp words(values, label), do: values |> Enum.map(label) |> Enum.join(", ")

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
