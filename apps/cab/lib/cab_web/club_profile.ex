defmodule CabWeb.ClubProfile do
  @moduledoc """
  Labels for the club profile facts (format, language, audience), the
  address of the club's logo and a refused save's message.
  """
  use Gettext, backend: CabWeb.Gettext

  alias Cab.Clubs.Club

  def format_options, do: Enum.map(Club.formats(), &{format(&1), &1})
  def language_options, do: Enum.map(Club.languages(), &{language(&1), &1})
  def audience_options, do: Enum.map(Club.audiences(), &{audience(&1), &1})

  @doc "The logo's path on cab, nil without one."
  def logo_path(%{logo: logo}) when is_binary(logo), do: Cab.Uploads.path(logo)
  def logo_path(_club), do: nil

  @doc "The logo's absolute address on cab (the API's logo_url), nil without one."
  def logo_url(club) do
    if path = logo_path(club), do: CabWeb.Endpoint.url() <> path
  end

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

  @doc "A refused profile save in one line: the first field that is wrong, and why."
  def save_error(%Ecto.Changeset{} = changeset) do
    case Cab.Text.first_error(
           changeset,
           ~w(name city meeting_info description contacts format_other language_other)a
         ) do
      {field, message} -> gettext("%{field}: %{error}", field: field_label(field), error: message)
      nil -> gettext("Something went wrong, try again.")
    end
  end

  defp field_label(:name), do: gettext("Club name")
  defp field_label(:city), do: gettext("City")
  defp field_label(:meeting_info), do: gettext("Meetings")
  defp field_label(:description), do: gettext("About the club")
  defp field_label(:contacts), do: gettext("Contacts")
  defp field_label(:format_other), do: gettext("Format")
  defp field_label(:language_other), do: gettext("Language")

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
