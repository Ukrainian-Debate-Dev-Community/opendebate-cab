defmodule CabWeb.TourHTML do
  @moduledoc "The guided tour's player."
  use CabWeb, :html

  alias CabWeb.Tour

  embed_templates "tour_html/*"

  @doc """
  The player's steps for the browser: the frame's address in place of
  its key, whose eyes, the chapter's index, and the step's hold.
  """
  def steps_json(tour) do
    chapters = Tour.chapters(tour)

    tour.steps
    |> Enum.map(fn step ->
      %{
        chapter: step.chapter,
        chapter_index: Enum.find_index(chapters, &(&1 == step.chapter)),
        text: step.text,
        as: step.as,
        where: step.frame && Tour.where(step.frame),
        src: step.frame && ~p"/tour/frame/#{step.frame}",
        target: step.target,
        set: Enum.map(step.set, fn {selector, value} -> [selector, value] end),
        fill: Enum.map(step.fill, fn {selector, value} -> [selector, value] end),
        click: step.click,
        hold: Tour.hold(step),
        finale: step.finale
      }
    end)
    |> Jason.encode!()
  end
end
