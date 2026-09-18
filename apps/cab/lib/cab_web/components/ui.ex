defmodule CabWeb.Ui do
  @moduledoc """
  cab-specific flow components on top of the `Core.Ui` design
  system: the tournament round/step strips wired to cab routes. The
  page chrome lives in `CabWeb.Layouts.app/1`; pure route-free
  components (statusline, guide, status_tag) live in `Core.Ui`.
  """

  use Phoenix.Component
  use Phoenix.VerifiedRoutes, endpoint: CabWeb.Endpoint, router: CabWeb.Router

  import Core.Ui

  @doc """
  cab2 tdFlow: rounds strip (R1..Rn, Final) plus, when `seq` names a
  preliminary round, the four-step strip for it. `steps_done` is how
  many of check-in / draw+motion / ballots / done are finished;
  `active` highlights the step of the current page. Both strips are
  rendered through `statusline/1`.
  """
  attr :event_id, :any, required: true
  attr :rounds, :list, default: []
  attr :seq, :any, default: nil
  attr :steps_done, :integer, default: 0
  attr :active, :any, default: nil

  def td_flow(assigns) do
    ~H"""
    <.statusline items={round_items(@event_id, @rounds, @seq)} />
    <.statusline
      :if={@seq && current_round_name(@rounds, @seq) != "Final"}
      items={step_items(@event_id, @seq, @steps_done, @active)}
      style="margin-top:6px;"
    />
    """
  end

  defp round_items(event_id, rounds, seq) do
    items =
      Enum.map(rounds, fn round ->
        %{
          label: if(round["name"] == "Final", do: "Final", else: "R#{round["sequence"]}"),
          state: round_state(round, rounds),
          sel: seq == round["sequence"],
          href: round_link(event_id, round)
        }
      end)

    # The upcoming-Final placeholder only applies to multi-round
    # tournaments; one-round events (club sessions) have no final.
    if Enum.any?(rounds, &(&1["name"] == "Final")) or length(rounds) < 2 do
      items
    else
      items ++ [%{label: "Final"}]
    end
  end

  defp step_items(event_id, seq, steps_done, active) do
    step_defs()
    |> Enum.with_index()
    |> Enum.map(fn {{label, step_key}, index} ->
      %{
        label: label,
        state: step_state(index, steps_done),
        sel: active == step_key && step_key != nil,
        href: step_key && step_href(event_id, seq, step_key)
      }
    end)
  end

  defp step_defs do
    [{"check-in", "checkin"}, {"draw + motion", "draw"}, {"ballots", "ballots"}, {"done", nil}]
  end

  defp step_href(event_id, seq, "checkin"), do: ~p"/t/#{event_id}/r/#{seq}/checkin"
  defp step_href(event_id, seq, "draw"), do: ~p"/t/#{event_id}/r/#{seq}/draw"
  defp step_href(event_id, seq, "ballots"), do: ~p"/t/#{event_id}/r/#{seq}/ballots"

  defp step_state(index, done) when index < done, do: "done"
  defp step_state(index, done) when index == done, do: "live"
  defp step_state(_index, _done), do: nil

  defp round_state(round, rounds) do
    cond do
      round["status"] == "completed" -> "done"
      first_open?(round, rounds) -> "live"
      true -> nil
    end
  end

  defp first_open?(round, rounds) do
    Enum.find(rounds, &(&1["status"] != "completed")) == round
  end

  defp current_round_name(rounds, seq) do
    case Enum.find(rounds, &(&1["sequence"] == seq)) do
      nil -> nil
      round -> round["name"]
    end
  end

  defp round_link(event_id, %{"name" => "Final", "sequence" => seq}),
    do: ~p"/t/#{event_id}/r/#{seq}/ballots"

  defp round_link(event_id, %{"sequence" => seq}),
    do: ~p"/t/#{event_id}/r/#{seq}/checkin"
end
