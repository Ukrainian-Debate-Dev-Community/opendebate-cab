defmodule CabWeb.TourHTML do
  @moduledoc "The guided tours' list and player."
  use CabWeb, :html

  embed_templates "tour_html/*"

  @doc "A tour's length in whole minutes (at least one)."
  def minutes(tour), do: max(1, round(Enum.sum(Enum.map(tour.steps, & &1.seconds)) / 60))

  @doc "The player's steps for the browser: the frame's address in place of its key."
  def steps_json(tour) do
    tour.steps
    |> Enum.map(fn step ->
      %{
        chapter: step.chapter,
        text: step.text,
        seconds: step.seconds,
        target: step.target,
        src: step.frame && ~p"/tour/frame/#{step.frame}"
      }
    end)
    |> Jason.encode!()
  end
end
