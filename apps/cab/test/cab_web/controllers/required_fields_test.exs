defmodule CabWeb.RequiredFieldsTest do
  @moduledoc """
  The forms on the pages: a required field is not filled by spaces,
  no-break spaces or zero-width characters; text is trimmed, capped
  and free of control characters; a refused form comes back as typed
  with the error on its field, and the inputs carry `required` and
  `maxlength` as the server checks them.
  """
  use CabWeb.ConnCase, async: true

  import Cab.Fixtures

  alias Cab.{Clubs, Repo}
  alias Cab.Sessions.Session

  @blanks ["   ", "  ", "​", " ﻿‍ "]

  defp log_in(conn, user) do
    conn
    |> init_test_session(%{user_id: user.id})
    |> Plug.Conn.put_private(:plug_skip_csrf_protection, true)
  end

  # any engine call fails the test: the checks come first
  defp no_engine do
    Req.Test.stub(Core.Engine, fn _conn -> flunk("the engine was called") end)
  end

  # the block of the field with this label, as rendered
  defp block(html, label) do
    [block] =
      Regex.run(
        ~r{<div class="f-block[^"]*">\s*<label class="q">\s*#{label}\b.*?(?=<div class="f-block|</form>)}s,
        html
      )

    block
  end

  defp field_error(html, label) do
    block = block(html, label)
    assert block =~ ~s(class="f-block err"), label
    [_, message] = Regex.run(~r{<div class="error">([^<]*)</div>}, block)
    message
  end

  setup %{conn: conn} do
    head = user_fixture(%{node_user_id: 9})

    club =
      club_fixture(head, %{name: "Kyiv Debate Club", city: "Kyiv", engine_organisation_id: 3})

    %{conn: log_in(conn, head), club: club}
  end

  describe "club profile" do
    test "the inputs say what the server checks", %{conn: conn, club: club} do
      html = conn |> get(~p"/c/#{club.uuid}/owner") |> html_response(200)
      max = Cab.Clubs.Club.max_lengths()

      assert block(html, "Club name") =~
               ~r{value="Kyiv Debate Club"\s+maxlength="#{max.name}"\s+required}

      assert block(html, "City") =~ ~r{value="Kyiv"\s+maxlength="#{max.city}"}
      refute block(html, "City") =~ "required"
      assert block(html, "About the club") =~ ~s(maxlength="#{max.description}")
    end

    test "a blank name is refused on its field, the rest kept as typed",
         %{conn: conn, club: club} do
      no_engine()

      for blank <- @blanks do
        html =
          conn
          |> post(~p"/c/#{club.uuid}/owner/club", %{"name" => blank, "city" => "Lviv"})
          |> html_response(422)

        assert field_error(html, "Club name") == "Fill this in."
        assert html =~ "Club name: Fill this in."
        assert html =~ ~s(name="city" value="Lviv")
      end

      assert Repo.reload(club).name == "Kyiv Debate Club"
      assert Repo.reload(club).city == "Kyiv"
    end

    test "over-long text and control characters are refused on their fields",
         %{conn: conn, club: club} do
      no_engine()

      for {field, value, label, message} <- [
            {"city", String.duplicate("x", 81), "City", "80 characters at most."},
            {"meeting_info", "a\u0007b", "Meetings",
             "Use plain text without control characters."},
            {"description", String.duplicate("x", 5001), "About the club",
             "5000 characters at most."},
            {"contacts", "@tg\u0000", "Contacts", "Use plain text without control characters."}
          ] do
        html =
          conn
          |> post(~p"/c/#{club.uuid}/owner/club", %{"name" => club.name, field => value})
          |> html_response(422)

        assert field_error(html, label) == message
      end

      html =
        conn
        |> post(~p"/c/#{club.uuid}/owner/club", %{
          "name" => club.name,
          "formats" => "other",
          "format_other" => String.duplicate("x", 61)
        })
        |> html_response(422)

      assert field_error(html, "Format") == "60 characters at most."
      assert Repo.reload(club).formats == []
    end
  end

  describe "open a session" do
    test "a garbled name or a bad limit is refused on its field before the engine",
         %{conn: conn, club: club} do
      no_engine()

      html =
        conn
        |> post(~p"/c/#{club.uuid}/owner/sessions", %{
          "name" => "Night\u0000",
          "max_participants" => "0"
        })
        |> html_response(422)

      assert field_error(html, "Session name") == "Use plain text without control characters."

      assert field_error(html, "Participant limit") ==
               "The participant limit is a whole number above zero, or empty for none."

      html =
        conn
        |> post(~p"/c/#{club.uuid}/owner/sessions", %{
          "name" => String.duplicate("x", 121),
          "max_participants" => "12"
        })
        |> html_response(422)

      assert field_error(html, "Session name") == "120 characters at most."
      assert html =~ ~s(name="max_participants" value="12")
      assert Repo.all(Session) == []
    end

    test "a name with nothing visible is no name: the session is named after the date",
         %{conn: conn, club: club} do
      html = conn |> get(~p"/c/#{club.uuid}/owner") |> html_response(200)
      assert html =~ ~s(name="name" maxlength="#{Cab.Sessions.max_lengths().name}")

      Req.Test.stub(Core.Engine, fn conn ->
        {:ok, body, conn} = Plug.Conn.read_body(conn)
        params = if body == "", do: %{}, else: Jason.decode!(body)

        data =
          case {conn.method, conn.request_path} do
            {"POST", "/api/events/3"} -> %{"id" => 11, "name" => params["name"]}
            {"POST", "/api/events/11/rounds"} -> %{"id" => 21, "sequence" => 1}
            {"GET", "/api/events/11/feedback-questions"} -> []
            {"POST", "/api/events/11/feedback-questions"} -> %{"id" => 1}
          end

        Req.Test.json(conn, %{"status" => "success", "data" => data})
      end)

      conn |> post(~p"/c/#{club.uuid}/owner/sessions", %{"name" => " ​ "})

      assert [%Session{name: name}] = Repo.all(Session)
      assert name == "Club session #{Date.utc_today()}"
    end
  end

  describe "display name" do
    test "a refused name stays typed with the error on its field", %{conn: conn} do
      html = conn |> post(~p"/account", %{"name" => "Ann\u0007"}) |> html_response(422)

      assert field_error(html, "Display name") == "Use plain text without control characters."
      assert html =~ "Display name: Use plain text without control characters."
    end
  end

  describe "admin: create a club" do
    setup %{conn: conn} do
      admin = user_fixture() |> Ecto.Changeset.change(is_admin: true) |> Repo.update!()
      %{conn: log_in(conn, admin), head: user_fixture()}
    end

    test "a blank name is refused on its field, the rest kept as typed",
         %{conn: conn, head: head} do
      no_engine()

      for blank <- @blanks do
        html =
          conn
          |> post(~p"/admin/clubs", %{"name" => blank, "city" => "Odesa", "head" => head.username})
          |> html_response(422)

        assert field_error(html, "Club name") == "Fill this in."
        assert html =~ ~s(name="city" value="Odesa")
        assert html =~ ~s(name="head" value="#{head.username}")
      end

      html =
        conn
        |> post(~p"/admin/clubs", %{
          "name" => "Odesa Club",
          "city" => "Odesa\u0000",
          "head" => head.username
        })
        |> html_response(422)

      assert field_error(html, "City") == "Use plain text without control characters."
      assert Clubs.list_all_clubs() |> Enum.filter(&(&1.city == "Odesa")) == []
    end
  end

  describe "registration form answers" do
    test "text answers carry the server's length; required ones are required",
         %{conn: conn, club: club} do
      club =
        form_fields_fixture(club, [
          %{"label" => "School", "type" => "text", "required" => "yes", "scope" => "both"},
          %{"label" => "About you", "type" => "longtext", "required" => "no", "scope" => "both"}
        ])

      user = user_fixture()
      html = conn |> log_in(user) |> get(~p"/c/#{club.uuid}/join") |> html_response(200)

      assert block(html, "School") =~ ~r{maxlength="200"\s+required}
      assert block(html, "About you") =~ ~s(maxlength="2000")
      refute block(html, "About you") =~ "required"
    end
  end
end
