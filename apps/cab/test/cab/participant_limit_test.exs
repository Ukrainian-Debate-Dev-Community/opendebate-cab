defmodule Cab.ParticipantLimitTest do
  @moduledoc """
  The participant limit: the column and its validation, the head
  setting it, and self-registration refused past it - also when two
  people race for the last place.
  """

  use Cab.DataCase, async: true

  import Cab.Fixtures

  alias Cab.{Registrations, Sessions}
  alias Cab.Sessions.Session

  setup do
    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})
    %{head: head, club: club}
  end

  defp ok(conn, data), do: Req.Test.json(conn, %{"status" => "success", "data" => data})

  # an engine whose event 11 keeps its participants in an Agent: every
  # add lands in the list the next read returns
  defp engine(participants) do
    {:ok, agent} = Agent.start_link(fn -> participants end)

    Req.Test.stub(Core.Engine, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)

      case {conn.method, conn.request_path} do
        {"GET", "/api/events/11"} ->
          ok(conn, %{"id" => 11, "status" => "scheduled"})

        {"GET", "/api/events/11/rounds"} ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        {"GET", "/api/events/11/participants"} ->
          ok(conn, Agent.get(agent, & &1))

        {"GET", "/api/rounds/21/rooms"} ->
          ok(conn, [])

        {"POST", "/api/events/11/participants"} ->
          # a slow engine widens the window two registrations race in
          Process.sleep(50)
          params = Jason.decode!(body)

          participant =
            Agent.get_and_update(agent, fn list ->
              added = %{
                "id" => 100 + length(list),
                "display_name" => params["display_name"],
                "user_id" => params["user_id"],
                "role" => "speaker",
                "raw_claim_token" => "token"
              }

              {added, list ++ [added]}
            end)

          ok(conn, participant)
      end
    end)

    agent
  end

  defp signups(n), do: for(i <- 1..n//1, do: %{"id" => i, "display_name" => "P#{i}"})

  defp guest_answers, do: %{"email" => "greta@example.com"}

  describe "the column" do
    test "a limit is a whole number above zero; nil is no limit" do
      valid = Session.changeset(%Session{engine_event_id: 11, max_participants: 12})
      assert valid.valid?
      assert Session.changeset(%Session{engine_event_id: 11}).valid?

      for bad <- [0, -3] do
        changeset = Session.changeset(%Session{engine_event_id: 11, max_participants: bad})
        assert %{max_participants: [_message]} = errors_on(changeset)

        assert %{max_participants: [_message]} =
                 errors_on(Session.limit_changeset(%Session{}, bad))
      end
    end

    test "the database refuses a limit of zero", %{club: club} do
      session = session_fixture(club)

      assert_raise Postgrex.Error, ~r/max_participants_positive/, fn ->
        Repo.update_all(from(s in Session, where: s.id == ^session.id),
          set: [max_participants: 0]
        )
      end
    end

    test "the form's limit parses; blank is none" do
      assert Sessions.parse_participant_limit(nil) == {:ok, nil}
      assert Sessions.parse_participant_limit(" ") == {:ok, nil}
      assert Sessions.parse_participant_limit(" 16 ") == {:ok, 16}

      for bad <- ["0", "-2", "ten", "1.5", 0] do
        assert {:error, message} = Sessions.parse_participant_limit(bad)
        assert message =~ "whole number above zero"
      end
    end
  end

  describe "the head" do
    test "sets the limit while sign-ups are open; cab records the count", %{club: club} do
      session = session_fixture(club)
      engine(signups(3))

      assert {:ok, %Session{max_participants: 5, signups_count: 3}} =
               Sessions.set_max_participants(session, "5")

      assert Sessions.places_left(Repo.get!(Session, session.id)) == 2

      assert {:ok, %Session{max_participants: nil}} = Sessions.set_max_participants(session, "")
      assert Sessions.places_left(Repo.get!(Session, session.id)) == nil
    end

    test "cannot set it once registration closed", %{club: club} do
      session = closed_session_fixture(club)
      engine([])

      assert {:error, :conflict, _message} = Sessions.set_max_participants(session, "5")
    end

    test "full is the limit reached", %{club: club} do
      session = session_fixture(club)
      refute Sessions.full?(session)
      refute Sessions.full?(%{session | max_participants: 2, signups_count: 1})
      assert Sessions.full?(%{session | max_participants: 2, signups_count: 2})
      assert Sessions.places_left(%{session | max_participants: 2, signups_count: 3}) == 0
    end
  end

  describe "registration" do
    test "is refused past the limit", %{club: club} do
      session = session_fixture(club, max_participants: 2)
      agent = engine(signups(2))
      user = user_fixture(%{node_user_id: 44})

      assert {:error, :conflict, "Registration is full."} =
               Registrations.register(user, session, %{})

      assert {:error, :conflict, "Registration is full."} =
               Registrations.register_guest(session, "Greta Guest", guest_answers())

      assert length(Agent.get(agent, & &1)) == 2
      assert Repo.get!(Session, session.id).signups_count == 2
    end

    test "takes the last place and counts it", %{club: club} do
      session = session_fixture(club, max_participants: 2)
      engine(signups(1))

      assert {:ok, _link} = Registrations.register_guest(session, "Greta Guest", guest_answers())

      session = Repo.get!(Session, session.id)
      assert session.signups_count == 2
      assert Sessions.full?(session)
      assert Sessions.club_sessions(club) |> hd() |> Map.fetch!(:status) == :full
    end

    test "two people racing for the last place: one gets it", %{club: club} do
      session = session_fixture(club, max_participants: 3)
      agent = engine(signups(2))

      results =
        ["Greta Guest", "Gina Guest"]
        |> Enum.map(fn name ->
          Task.async(fn -> Registrations.register_guest(session, name, guest_answers()) end)
        end)
        |> Task.await_many(10_000)

      assert [{:error, :conflict, "Registration is full."}] =
               Enum.reject(results, &match?({:ok, _}, &1))

      assert length(Agent.get(agent, & &1)) == 3
      assert Repo.get!(Session, session.id).signups_count == 3
    end

    test "no limit: nobody is refused", %{club: club} do
      session = session_fixture(club)
      engine(signups(40))

      assert {:ok, _link} = Registrations.register_guest(session, "Greta Guest", guest_answers())
    end
  end
end
