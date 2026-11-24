defmodule CabWeb.SessionStepsTest do
  use ExUnit.Case, async: true

  import CabWeb.OwnerHTML, only: [session_step: 1]

  test "registration, then rooms, then debates, then finished - none skipped" do
    pending = %{"id" => 1, "status" => "pending", "Motion" => nil}

    assert session_step(%{stage: :signup, rooms: []}) == :registration
    assert session_step(%{stage: :closed, rooms: []}) == :rooms
    # Start session made the rooms: no motion out yet
    assert session_step(%{stage: :running, rooms: [pending]}) == :rooms
    # the first motion out
    assert session_step(%{stage: :running, rooms: [%{pending | "Motion" => %{"id" => 3}}]}) ==
             :debates

    # or a ballot moving
    assert session_step(%{stage: :running, rooms: [%{pending | "status" => "judging"}]}) ==
             :debates

    assert session_step(%{stage: :done, rooms: [pending]}) == :finished
  end
end
