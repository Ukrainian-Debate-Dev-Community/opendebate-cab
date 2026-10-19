defmodule Cab.FormTextTest do
  @moduledoc """
  Every form's text, checked by the context behind it: required text
  with only spaces, no-break spaces or zero-width characters in it is
  blank, optional text like that is nil, and over-long text or control
  characters are refused before anything reaches the engine.
  """
  use Cab.DataCase, async: true

  import Cab.Fixtures

  alias Cab.{Accounts, Clubs, HeadInvitations, Links, Sessions}

  @blanks ["   ", "\u00A0\u00A0", "\u200B", "\u200B\u200C\u200D", "\uFEFF", " \u00A0\u200B "]

  # any engine call fails the test: the checks come first
  defp no_engine do
    Req.Test.stub(Core.Engine, fn _conn -> flunk("the engine was called") end)
  end

  defp ok_engine do
    Req.Test.stub(Core.Engine, fn conn ->
      Req.Test.json(conn, %{"status" => "success", "data" => %{"id" => 3, "name" => "x"}})
    end)
  end

  describe "Cab.Text" do
    test "check/2 words the codes and takes the field's own message" do
      assert Cab.Text.check(" \u200Bok\u00A0") == {:ok, "ok"}
      assert Cab.Text.check("\u200B") == {:ok, nil}
      assert Cab.Text.check("\u200B", required: true) == {:error, "Fill this in."}

      assert Cab.Text.check(nil, required: true, message: "Enter a name.") ==
               {:error, "Enter a name."}

      assert Cab.Text.check("abc", max: 2) == {:error, "2 characters at most."}

      assert Cab.Text.check("a\u0000b") ==
               {:error, "Use plain text without control characters."}
    end

    test "first_error/2 picks the first field in the given order" do
      changeset =
        %Cab.Clubs.Club{}
        |> Ecto.Changeset.change()
        |> Ecto.Changeset.add_error(:city, "%{count} characters at most.", count: 80)
        |> Ecto.Changeset.add_error(:name, "Enter a name.")

      assert Cab.Text.first_error(changeset, [:name, :city]) == {:name, "Enter a name."}
      assert Cab.Text.first_error(changeset, [:city]) == {:city, "80 characters at most."}
      assert Cab.Text.first_error(changeset, [:contacts]) == nil
    end
  end

  describe "club profile" do
    setup do
      head = user_fixture(%{node_user_id: 9})
      %{head: head, club: club_fixture(head, %{name: "Old Name", city: "Kyiv"})}
    end

    test "a new club needs a visible name; nothing is made in the engine without one",
         %{head: head} do
      no_engine()

      for blank <- @blanks do
        assert {:error, changeset} = Clubs.create_club(blank, "Kyiv", head)
        assert %{name: ["Fill this in."]} = errors_on(changeset)
      end

      assert {:error, changeset} = Clubs.create_club(String.duplicate("x", 121), nil, head)
      assert %{name: ["120 characters at most."]} = errors_on(changeset)

      assert {:error, changeset} = Clubs.create_club("Kyiv\u0000Club", nil, head)
      assert %{name: ["Use plain text without control characters."]} = errors_on(changeset)
    end

    test "a new club's name and city reach the engine and the row trimmed", %{head: head} do
      test_pid = self()

      Req.Test.stub(Core.Engine, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        send(test_pid, {:org_name, Jason.decode!(body)["name"]})
        Req.Test.json(conn, %{"status" => "success", "data" => %{"id" => 5}})
      end)

      assert {:ok, club} = Clubs.create_club("\u200B Lviv Debate\u00A0", "\uFEFFLviv ", head)
      assert {club.name, club.city} == {"Lviv Debate", "Lviv"}
      assert_received {:org_name, "Lviv Debate"}
    end

    test "an edit keeps the name required and the engine untouched when refused",
         %{club: club} do
      no_engine()

      for blank <- @blanks do
        assert {:error, changeset} = Clubs.update_club(club, %{"name" => blank})
        assert %{name: ["Fill this in."]} = errors_on(changeset)
      end

      assert {:error, changeset} =
               Clubs.update_club(club, %{"name" => "New Name", "description" => "a\u0007b"})

      assert %{description: ["Use plain text without control characters."]} =
               errors_on(changeset)

      assert Repo.reload(club).name == "Old Name"
    end

    test "optional fields: invisible is nil, long texts keep their lines, limits hold",
         %{club: club} do
      ok_engine()

      assert {:ok, club} =
               Clubs.update_club(club, %{
                 "city" => "\u00A0\u200B",
                 "meeting_info" => " Thursdays 18:30\u200B",
                 "description" => "\r\nWe debate.\r\n\tEvery week.\r\n",
                 "contacts" => "\uFEFF"
               })

      assert club.city == nil
      assert club.meeting_info == "Thursdays 18:30"
      assert club.description == "We debate.\n\tEvery week."
      assert club.contacts == nil

      for {field, max} <- [city: 80, meeting_info: 300, description: 5000, contacts: 500] do
        assert {:error, changeset} =
                 Clubs.update_club(club, %{to_string(field) => String.duplicate("x", max + 1)})

        assert errors_on(changeset)[field] == ["#{max} characters at most."]

        assert {:ok, _} =
                 Clubs.update_club(club, %{to_string(field) => String.duplicate("x", max)})
      end

      assert {:error, changeset} = Clubs.update_club(club, %{"city" => "Ky\niv"})
      assert errors_on(changeset)[:city] == ["Use plain text without control characters."]
    end

    test "the other format's text is cleaned like the rest", %{club: club} do
      ok_engine()

      assert {:ok, club} =
               Clubs.update_club(club, %{"formats" => ["other"], "format_other" => "\u200B\u00A0"})

      assert club.format_other == nil

      assert {:error, changeset} =
               Clubs.update_club(club, %{
                 "formats" => ["other"],
                 "format_other" => String.duplicate("x", 61)
               })

      assert errors_on(changeset)[:format_other] == ["60 characters at most."]
    end
  end

  describe "join request" do
    setup do
      head = user_fixture()
      %{club: club_fixture(head), user: user_fixture()}
    end

    test "both answers need visible text", %{club: club, user: user} do
      for blank <- @blanks do
        assert {:error, changeset} =
                 Clubs.request_join(user, club, %{"message" => blank, "contact" => blank})

        assert %{message: [_], contact: [_]} = errors_on(changeset)
      end
    end

    test "over-long or garbled answers are refused; good ones are trimmed",
         %{club: club, user: user} do
      assert {:error, changeset} =
               Clubs.request_join(user, club, %{
                 "message" => String.duplicate("x", 2001),
                 "contact" => "@tg\u0000"
               })

      assert errors_on(changeset) == %{
               message: ["2000 characters at most."],
               contact: ["Use plain text without control characters."]
             }

      assert {:error, changeset} =
               Clubs.request_join(user, club, %{
                 "message" => "Hi",
                 "contact" => String.duplicate("x", 201)
               })

      assert errors_on(changeset) == %{contact: ["200 characters at most."]}

      assert {:ok, membership} =
               Clubs.request_join(user, club, %{
                 "message" => "\u200BI study law.\r\nI debated at school.\u00A0",
                 "contact" => " @tg\uFEFF"
               })

      assert {membership.message, membership.contact} ==
               {"I study law.\nI debated at school.", "@tg"}
    end
  end

  describe "display name" do
    test "is trimmed, nil when invisible, at most 120 characters" do
      user = user_fixture(%{name: "Ann"})

      assert {:ok, %{name: "Ann Lee"}} = Accounts.update_profile(user, %{"name" => "\u200B Ann Lee\u00A0"})
      assert {:ok, %{name: nil}} = Accounts.update_profile(user, %{"name" => "\u200B\u00A0"})

      assert {:error, changeset} =
               Accounts.update_profile(user, %{"name" => String.duplicate("x", 121)})

      assert errors_on(changeset) == %{name: ["120 characters at most."]}

      assert {:error, changeset} = Accounts.update_profile(user, %{"name" => "An\u0085n"})
      assert errors_on(changeset) == %{name: ["Use plain text without control characters."]}
    end
  end

  describe "guest name" do
    setup do
      head = user_fixture(%{node_user_id: 9})
      club = club_fixture(head)
      %{session: session_fixture(club)}
    end

    test "is refused before the engine when blank, over-long or garbled", %{session: session} do
      no_engine()

      for blank <- [nil | @blanks] do
        assert {:error, %{name: "Enter a name."}} = Links.register_guest(session, blank)
        assert {:error, %{name: "Enter a name."}} = Links.register_guest(session, blank, %{})
      end

      assert {:error, %{name: "120 characters at most."}} =
               Links.register_guest(session, String.duplicate("x", 121))

      assert {:error, %{name: "Use plain text without control characters."}} =
               Links.register_guest(session, "Greta\tGuest")
    end
  end

  describe "head invitation" do
    test "the address and the name are checked and trimmed" do
      assert HeadInvitations.check_invitee(" \u200Bnew@example.com\u00A0", " \uFEFFNina ") ==
               {:ok, "new@example.com", "Nina"}

      for blank <- @blanks do
        assert HeadInvitations.check_invitee("new@example.com", blank) ==
                 {:error, "Type their name for the invitation."}

        assert HeadInvitations.check_invitee(blank, "Nina") ==
                 {:error, "Type an e-mail address to invite someone new."}
      end

      assert HeadInvitations.check_invitee("new@example.com", String.duplicate("x", 121)) ==
               {:error, "120 characters at most."}

      assert HeadInvitations.check_invitee("new@example.com", "Ni\u0000na") ==
               {:error, "Use plain text without control characters."}

      for bad <- [
            "ne\u200Bw@example.com",
            "new@exa\u0000mple.com",
            String.duplicate("a", 250) <> "@example.com"
          ] do
        assert {:error, _} = HeadInvitations.check_invitee(bad, "Nina")
      end
    end
  end

  describe "session name and motion" do
    setup do
      head = user_fixture(%{node_user_id: 9})
      club = club_fixture(head, %{engine_organisation_id: 3})
      %{head: head, club: club, session: session_fixture(club)}
    end

    test "an over-long or garbled session name is refused before the engine",
         %{head: head, club: club} do
      no_engine()

      assert {:error, "120 characters at most."} =
               Sessions.open(head, club, String.duplicate("x", 121))

      assert {:error, "Use plain text without control characters."} =
               Sessions.open(head, club, "Night\u0000")
    end

    test "the motion is required; infoslide and keyword are cleaned and capped" do
      for blank <- [nil | @blanks] do
        assert Sessions.clean_motion(blank, %{}) == {:error, "Type the motion."}
      end

      assert Sessions.clean_motion(" \u200BTHW ban cars\u00A0", %{
               "infoslide" => "\r\nCities.\r\n\tCars.\u200B",
               "keyword" => "\uFEFF"
             }) == {:ok, "THW ban cars", %{infoslide: "Cities.\n\tCars.", keyword: nil}}

      assert Sessions.clean_motion("THW", %{infoslide: "  "}) == {:ok, "THW", %{infoslide: nil}}

      assert Sessions.clean_motion(String.duplicate("x", 1001), %{}) ==
               {:error, "1000 characters at most."}

      assert Sessions.clean_motion("THW", %{"infoslide" => String.duplicate("x", 5001)}) ==
               {:error, "5000 characters at most."}

      assert Sessions.clean_motion("THW", %{"keyword" => String.duplicate("x", 33)}) ==
               {:error, "32 characters at most."}

      assert Sessions.clean_motion("THW\u0007", %{}) ==
               {:error, "Use plain text without control characters."}
    end

    test "a refused motion never reaches the engine", %{head: head, session: session} do
      no_engine()
      assert {:error, "Type the motion."} = Sessions.set_room_motion(head, session, 31, "\u200B")
    end
  end
end
