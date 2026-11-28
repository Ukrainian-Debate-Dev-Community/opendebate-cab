defmodule CabWeb.DebateWordsTest do
  @moduledoc """
  cab speaks debating: results as debaters say them per format (BP
  places, Australs won / lost), teams by their side and speakers (never
  the engine's team names), a question's own mark before an answer.
  """
  use ExUnit.Case, async: true

  import Phoenix.Component
  import Phoenix.LiveViewTest

  alias CabWeb.SessionFormat

  @bp Cab.Format.of(%Cab.Sessions.Session{format: "bp"})
  @aus Cab.Format.of(%Cab.Sessions.Session{format: "aus"})

  test "BP places its four teams; two teams win or lose" do
    assert Enum.map(1..4, &SessionFormat.place_words(&1, @bp)) == ["1st", "2nd", "3rd", "4th"]
    assert SessionFormat.place_words(1, @aus) == "won"
    assert SessionFormat.place_words(2, @aus) == "lost"
    assert SessionFormat.team_points?(@bp)
    refute SessionFormat.team_points?(@aus)
  end

  test "a team that sent feedback is its side and speakers" do
    room = %{
      "id" => 71,
      "RoomTeams" => [
        %{
          "position" => 2,
          "Team" => %{"id" => 1002, "name" => "Team 1.2"},
          "RoomSpeakers" => [
            %{"id" => 1, "EventParticipant" => %{"display_name" => "Anna"}},
            %{"id" => 2, "EventParticipant" => %{"display_name" => "Yurii"}}
          ]
        }
      ]
    }

    label =
      SessionFormat.feedback_team_label(%{rooms: [room]}, %{room_id: 71, team_id: 1002}, @bp)

    assert label == "OO - Anna & Yurii"

    assert SessionFormat.feedback_team_label(%{rooms: [room]}, %{room_id: 9, team_id: 1}, @bp) ==
             "—"
  end

  test "an answer follows its question without a doubled mark" do
    assigns = %{
      answers: [
        %{"id" => "q", "label" => "How long have you been debating?", "value" => "Up to a year"},
        %{"id" => "email", "label" => "Your e-mail", "type" => "email", "value" => "a@b.c"}
      ]
    }

    html = rendered_to_string(~H"<Ui.FormComponents.form_answers answers={@answers} />")
    assert html =~ "How long have you been debating? Up to a year"
    refute html =~ "?:"
    assert html =~ "Your e-mail:"
  end
end
