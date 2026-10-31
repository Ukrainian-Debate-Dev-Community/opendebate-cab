defmodule Public.ICal do
  @moduledoc "The public calendar as an iCalendar feed (RFC 5545), all-day events."

  alias Public.Events.Event

  @doc "`language` gives an event's language line for the description, or nil."
  def feed(events, host, language \\ fn _event -> nil end) do
    lines =
      ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//public//calendar//EN", "CALSCALE:GREGORIAN"] ++
        Enum.flat_map(events, &event(&1, host, language.(&1))) ++ ["END:VCALENDAR"]

    Enum.map_join(lines, "", &(fold(&1) <> "\r\n"))
  end

  defp event(%Event{} = e, host, language) do
    last = e.ends_on || e.starts_on
    description = [language, e.details] |> Enum.reject(&(&1 in [nil, ""])) |> Enum.join("\n\n")

    [
      "BEGIN:VEVENT",
      "UID:event-#{e.id}@#{host}",
      "DTSTAMP:" <> stamp(e.updated_at),
      "DTSTART;VALUE=DATE:" <> day(e.starts_on),
      "DTEND;VALUE=DATE:" <> day(Date.add(last, 1)),
      "SUMMARY:" <> escape(e.title)
    ] ++
      if(e.city, do: ["LOCATION:" <> escape(e.city)], else: []) ++
      if(description != "", do: ["DESCRIPTION:" <> escape(description)], else: []) ++
      if(e.link, do: ["URL:" <> e.link], else: []) ++ ["END:VEVENT"]
  end

  defp day(date), do: Calendar.strftime(date, "%Y%m%d")

  defp stamp(nil), do: stamp(DateTime.utc_now())
  defp stamp(at), do: Calendar.strftime(at, "%Y%m%dT%H%M%SZ")

  defp escape(text) do
    text
    |> String.replace("\\", "\\\\")
    |> String.replace(";", "\;")
    |> String.replace(",", "\\,")
    |> String.replace(~r/\r?\n/, "\\n")
  end

  # lines longer than 75 octets continue on the next line after a space
  defp fold(line) when byte_size(line) <= 75, do: line

  defp fold(line) do
    {head, rest} = split_at_octets(line, 75)
    head <> "\r\n " <> fold(rest)
  end

  defp split_at_octets(line, n) do
    chars = String.graphemes(line)

    {head, rest, _} =
      Enum.reduce(chars, {"", "", 0}, fn ch, {h, r, size} ->
        if r == "" and size + byte_size(ch) <= n,
          do: {h <> ch, r, size + byte_size(ch)},
          else: {h, r <> ch, size}
      end)

    {head, rest}
  end
end
