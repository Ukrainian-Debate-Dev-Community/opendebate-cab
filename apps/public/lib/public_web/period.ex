defmodule PublicWeb.Period do
  @moduledoc """
  What the calendars show: one month (`?month=YYYY-MM`, the default),
  one year (`?view=year&year=YYYY`) or every event (`?view=all`).
  """

  alias PublicWeb.Month

  defstruct view: :month, first: nil

  def parse(params) do
    case params["view"] do
      "all" -> %__MODULE__{view: :all}
      "year" -> %__MODULE__{view: :year, first: year_start(params["year"])}
      _ -> %__MODULE__{view: :month, first: Month.parse(params["month"])}
    end
  end

  def month(%Date{} = first), do: %__MODULE__{view: :month, first: first}
  def year(%Date{} = first), do: %__MODULE__{view: :year, first: first}
  def all, do: %__MODULE__{view: :all}

  # the dates the period covers; nil for every event
  def range(%__MODULE__{view: :all}), do: nil
  def range(%__MODULE__{view: :month, first: first}), do: {first, Date.end_of_month(first)}
  def range(%__MODULE__{view: :year, first: first}), do: {first, Date.new!(first.year, 12, 31)}

  def prev(%__MODULE__{view: :month, first: first} = p), do: %{p | first: Month.prev(first)}
  def prev(%__MODULE__{view: :year, first: first} = p), do: %{p | first: shift_year(first, -1)}

  def next(%__MODULE__{view: :month, first: first} = p), do: %{p | first: Month.next(first)}
  def next(%__MODULE__{view: :year, first: first} = p), do: %{p | first: shift_year(first, 1)}

  # the query parameters that bring the period back
  def params(%__MODULE__{view: :month, first: first}), do: [month: Month.param(first)]
  def params(%__MODULE__{view: :year, first: first}), do: [view: "year", year: first.year]
  def params(%__MODULE__{view: :all}), do: [view: "all"]

  defp year_start(value) do
    with value when is_binary(value) <- value,
         {year, ""} <- Integer.parse(value),
         {:ok, date} <- Date.new(year, 1, 1) do
      date
    else
      _ -> Date.new!(Date.utc_today().year, 1, 1)
    end
  end

  defp shift_year(first, by), do: Date.new!(first.year + by, 1, 1)
end
