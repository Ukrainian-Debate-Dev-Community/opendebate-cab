defmodule CabWeb.ResponsesCsv do
  @moduledoc """
  A session's form responses as a CSV file the head downloads
  (`Cab.Links.responses/1`): name, registration time, then one column
  per form field. Written by hand: semicolon-separated (what Excel
  expects in a Ukrainian or most European locales; Google Sheets and
  Numbers detect it too), RFC 4180 quoting with CRLF line ends, UTF-8
  with a byte order mark so Excel opens Ukrainian text correctly, and a
  guest's answer that would start a spreadsheet formula is kept as text.
  """

  use Gettext, backend: CabWeb.Gettext

  alias CabWeb.FormComponents

  @bom <<0xEF, 0xBB, 0xBF>>

  @doc "The whole file: BOM, header row, one row per guest."
  def encode(%{columns: columns, rows: rows}) do
    header =
      [gettext("Name"), gettext("Registered (UTC)")] ++
        Enum.map(columns, &FormComponents.field_label/1)

    lines =
      for row <- rows do
        [row.name, registered(row.registered_at)] ++
          for column <- columns, do: answer(row.answers[column["label"]])
      end

    IO.iodata_to_binary([@bom | Enum.map([header | lines], &line/1)])
  end

  @doc """
  The download's file name: club, session name and date, e.g.
  "Kyiv Debate Club - Tuesday night - 2026-10-13 - responses.csv",
  without characters file systems refuse.
  """
  def filename(club, session) do
    date = Date.to_iso8601(session.scheduled_at || session.inserted_at)

    [club.name, session.name, date, gettext("responses")]
    |> Enum.reject(&(&1 in [nil, ""]))
    |> Enum.join(" - ")
    |> String.replace(~r{[/\\:*?"<>|\x00-\x1F\x7F]+}u, "-")
    |> String.replace(~r/\s+/u, " ")
    |> String.trim()
    |> Kernel.<>(".csv")
  end

  @doc """
  A Content-Disposition value for `filename`: an ASCII fallback for
  old clients and the exact UTF-8 name (RFC 6266).
  """
  def disposition(filename) do
    fallback =
      filename
      |> String.replace(~r/[^A-Za-z0-9 ._-]+/, "_")
      |> String.replace(~r/_+/, "_")

    ~s(attachment; filename="#{fallback}"; filename*=UTF-8''#{URI.encode(filename, &URI.char_unreserved?/1)})
  end

  defp line(fields), do: [Enum.map_join(fields, ";", &field/1), "\r\n"]

  @doc false
  def field(nil), do: ""

  def field(value) when is_binary(value) do
    value = defuse(value)

    if String.match?(value, ~r/[";,\r\n]|^\s|\s$/u),
      do: ~s(") <> String.replace(value, ~s("), ~s("")) <> ~s("),
      else: value
  end

  # = + - @ (and tab/CR) open a formula in a spreadsheet: such an
  # answer gets a leading apostrophe, unless it is plainly a number or
  # a phone number ("+380 44 123 45 67", "-5")
  defp defuse(value) do
    cond do
      String.match?(value, ~r/^[+-]?[0-9][0-9 ().-]*$/) -> value
      String.match?(value, ~r/^[=+\-@\t\r]/) -> "'" <> value
      true -> value
    end
  end

  defp registered(nil), do: ""
  defp registered(at), do: Calendar.strftime(at, "%Y-%m-%d %H:%M")

  defp answer(nil), do: ""
  defp answer(answer), do: FormComponents.answer_text(answer)
end
