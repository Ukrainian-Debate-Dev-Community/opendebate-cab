defmodule PublicWeb.Month do
  @moduledoc "The ?month=YYYY-MM parameter of the calendars."

  def parse(value) do
    with value when is_binary(value) <- value,
         [y, m] <- String.split(value, "-"),
         {year, ""} <- Integer.parse(y),
         {month, ""} <- Integer.parse(m),
         {:ok, date} <- Date.new(year, month, 1) do
      date
    else
      _ -> Date.beginning_of_month(Date.utc_today())
    end
  end

  def param(%Date{} = first), do: Calendar.strftime(first, "%Y-%m")
  def prev(%Date{} = first), do: first |> Date.add(-1) |> Date.beginning_of_month()
  def next(%Date{} = first), do: first |> Date.end_of_month() |> Date.add(1)
end
