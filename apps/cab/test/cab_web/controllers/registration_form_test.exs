defmodule CabWeb.RegistrationFormTest do
  @moduledoc """
  The club's guest registration form (a Core.Forms definition on the
  club): the head's editor page, the guest's answers on /r/:sess, the
  personal link e-mailed to an answered address, and who sees the
  answers (the head only).
  """

  use CabWeb.ConnCase, async: true

  import Cab.Fixtures
  import Swoosh.TestAssertions

  alias Cab.Links.Link
  alias Cab.Repo

  setup %{conn: conn} do
    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})
    member = user_fixture(%{node_user_id: 77})
    membership_fixture(member, club)
    %{conn: conn, head: head, club: club, member: member}
  end

  defp log_in(conn, user) do
    conn
    |> init_test_session(%{user_id: user.id})
    |> Plug.Conn.put_private(:plug_skip_csrf_protection, true)
  end

  defp anon(conn), do: Plug.Conn.put_private(conn, :plug_skip_csrf_protection, true)

  defp ok(conn, data), do: Req.Test.json(conn, %{"status" => "success", "data" => data})

  defp stub_stage(signups) do
    test_pid = self()

    Req.Test.stub(Core.Engine, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/11"} ->
          ok(conn, %{"id" => 11, "name" => "Guest night", "status" => "scheduled"})

        {"GET", "/api/events/11/rounds"} ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        {"GET", "/api/events/11/participants"} ->
          ok(conn, signups)

        {"GET", "/api/rounds/21/rooms"} ->
          ok(conn, [])

        {"POST", "/api/events/11/participants"} ->
          send(test_pid, :engine_signup)
          ok(conn, %{"id" => 41, "role" => "speaker", "raw_claim_token" => "tok-41"})
      end
    end)
  end

  # the built-in e-mail (required), then phone, a yes/no and a
  # multiple choice
  defp with_form(club) do
    {:ok, club} =
      Cab.Clubs.edit_registration_form(club, fn form ->
        with {:ok, form} <- Core.Forms.add_field(form, %{"label" => "Phone", "type" => "phone"}),
             {:ok, form} <-
               Core.Forms.add_field(form, %{"label" => "First time?", "type" => "yesno"}) do
          Core.Forms.add_field(form, %{
            "label" => "Days",
            "type" => "multi",
            "options" => "Monday\nThursday"
          })
        end
      end)

    ids = Map.new(Cab.Clubs.guest_form(club), &{&1["label"], &1["id"]})
    {club, ids}
  end

  # ---------------------------------------------------------------
  # The editor
  # ---------------------------------------------------------------

  describe "editor" do
    test "the head's pages carry it in the top bar; only the head opens it",
         %{conn: conn, club: club, head: head, member: member} do
      club_page = conn |> log_in(head) |> get(~p"/c/#{club.uuid}/owner") |> html_response(200)
      assert club_page =~ ~s(href="/c/#{club.uuid}/owner/form")
      assert club_page =~ "Registration form"

      html = conn |> log_in(head) |> get(~p"/c/#{club.uuid}/owner/form") |> html_response(200)
      assert html =~ ~s(id="guest-form-editor")
      # the built-in name and e-mail lead the list; the e-mail only edits
      assert html =~ ~s(id="field-fixed")
      assert html =~ "Your name"
      assert html =~ ~s(id="field-email")
      assert html =~ "Your e-mail"
      assert html =~ ~s(href="/c/#{club.uuid}/owner/form?edit=email")
      refute html =~ "/owner/form/fields/email/remove"
      refute html =~ "/owner/form/fields/email/move"
      assert html =~ ~s(action="/c/#{club.uuid}/owner/form/fields")
      # one gold action, in the top bar; preview beside it; no button in the form
      assert html =~ ~s(form="field-form" class="go")
      assert html =~ ~s(href="/c/#{club.uuid}/owner/form/preview")
      refute html =~ ~s(class="f-submit")

      assert conn |> log_in(member) |> get(~p"/c/#{club.uuid}/owner/form") |> response(403)

      assert conn
             |> log_in(member)
             |> post(~p"/c/#{club.uuid}/owner/form/fields", %{label: "X", type: "text"})
             |> response(403)

      assert Repo.reload!(club).guest_form == []
    end

    test "add, refuse, edit, move and remove fields", %{conn: conn, club: club, head: head} do
      fields = ~p"/c/#{club.uuid}/owner/form/fields"

      added =
        conn
        |> log_in(head)
        |> post(fields, %{label: "Phone", type: "phone", required: "yes", hint: "for the day"})

      assert redirected_to(added) == "/c/#{club.uuid}/owner/form"
      assert Phoenix.Flash.get(added.assigns.flash, :info) == "Field added."

      conn
      |> log_in(head)
      |> post(fields, %{label: "Level", type: "choice", required: "no", options: "novice\nopen"})

      assert [
               %{"id" => "email", "locked" => true},
               %{"id" => phone_id, "label" => "Phone", "required" => true},
               %{"id" => level_id}
             ] = Cab.Clubs.guest_form(Repo.reload!(club))

      # a refused field re-renders the editor with the message and the values
      refused =
        conn
        |> log_in(head)
        |> post(fields, %{label: "Days", type: "multi", options: "only one"})
        |> html_response(422)

      assert refused =~ "Give 2 to 20 options, one per line."
      assert refused =~ "only one"
      assert length(Cab.Clubs.guest_form(Repo.reload!(club))) == 3

      edit_page =
        conn
        |> log_in(head)
        |> get(~p"/c/#{club.uuid}/owner/form?edit=#{phone_id}")
        |> html_response(200)

      assert edit_page =~ ~s(action="/c/#{club.uuid}/owner/form/fields/#{phone_id}")
      assert edit_page =~ "for the day"

      conn
      |> log_in(head)
      |> post("#{fields}/#{phone_id}", %{label: "Mobile", type: "phone", required: "no"})

      conn |> log_in(head) |> post("#{fields}/#{level_id}/move/up")

      assert [
               %{"id" => "email"},
               %{"id" => ^level_id},
               %{"id" => ^phone_id, "label" => "Mobile", "required" => false}
             ] = Cab.Clubs.guest_form(Repo.reload!(club))

      # nothing moves above the built-in e-mail
      blocked = conn |> log_in(head) |> post("#{fields}/#{level_id}/move/up")
      assert Phoenix.Flash.get(blocked.assigns.flash, :error) =~ "always asked"

      conn |> log_in(head) |> post("#{fields}/#{level_id}/remove")
      assert [%{"id" => "email"}, %{"id" => ^phone_id}] = Cab.Clubs.guest_form(Repo.reload!(club))

      assert conn |> log_in(head) |> post("#{fields}/nope/remove") |> response(404)
      assert conn |> log_in(head) |> post("#{fields}/#{phone_id}/move/sideways") |> response(404)
    end

    test "the built-in e-mail: only required and hint change; never removed or moved",
         %{conn: conn, club: club, head: head} do
      fields = ~p"/c/#{club.uuid}/owner/form/fields"

      edit =
        conn
        |> log_in(head)
        |> get(~p"/c/#{club.uuid}/owner/form?edit=email")
        |> html_response(200)

      assert edit =~ ~s(action="/c/#{club.uuid}/owner/form/fields/email")
      assert edit =~ ~s(name="required")
      refute edit =~ ~s(name="label")
      refute edit =~ ~s(name="type")
      refute edit =~ "Remove field"

      conn
      |> log_in(head)
      |> post("#{fields}/email", %{
        required: "no",
        hint: "for your link",
        label: "X",
        type: "text"
      })

      assert [email] = Cab.Clubs.guest_form(Repo.reload!(club))

      assert %{
               "label" => "Your e-mail",
               "type" => "email",
               "required" => false,
               "hint" => "for your link",
               "locked" => true
             } = email

      for path <- ["#{fields}/email/remove", "#{fields}/email/move/down"] do
        refused = conn |> log_in(head) |> post(path)
        assert redirected_to(refused) == "/c/#{club.uuid}/owner/form"
        assert Phoenix.Flash.get(refused.assigns.flash, :error) =~ "always asked"
      end

      assert [%{"id" => "email"}] = Cab.Clubs.guest_form(Repo.reload!(club))
    end

    test "preview shows the guest form for the head only, with nothing to send",
         %{conn: conn, club: club, head: head, member: member} do
      {club, ids} = with_form(club)
      path = ~p"/c/#{club.uuid}/owner/form/preview"

      html = conn |> log_in(head) |> get(path) |> html_response(200)
      assert html =~ "Preview: this is what a guest sees"
      assert html =~ ~s(id="guest-register-form")
      assert html =~ ~s(name="name")
      assert html =~ ~s(name="answers[email]")
      assert html =~ ~s(name="answers[#{ids["Days"]}][]")
      assert html =~ ~r/class="btn-go"\s+disabled/
      assert html =~ ~s(href="/c/#{club.uuid}/owner/form")

      assert conn |> log_in(member) |> get(path) |> response(403)
      assert redirected_to(get(conn, path)) =~ "/signin"
    end
  end

  # ---------------------------------------------------------------
  # The guest form on /r/:sess
  # ---------------------------------------------------------------

  describe "guest registration" do
    test "guests see the club's fields after the name; signed-in members do not",
         %{conn: conn, club: club, member: member} do
      {club, ids} = with_form(club)
      session = session_fixture(club, engine_event_id: 11)
      stub_stage([])

      html = conn |> get(~p"/r/#{session.uuid}") |> html_response(200)
      assert html =~ ~s(name="name")
      assert html =~ ~s(name="answers[#{"email"}]")
      assert html =~ ~s(type="email")
      assert html =~ ~s(name="answers[#{ids["Phone"]}]")
      assert html =~ ~s(name="answers[#{ids["Days"]}][]")
      assert html =~ "Thursday"

      signed_in = conn |> log_in(member) |> get(~p"/r/#{session.uuid}") |> html_response(200)
      assert signed_in =~ ~s(id="register-form")
      refute signed_in =~ "answers["
    end

    test "a missing or invalid answer re-renders with values kept; nothing is created",
         %{conn: conn, club: club} do
      {club, ids} = with_form(club)
      session = session_fixture(club, engine_event_id: 11)
      stub_stage([])

      html =
        conn
        |> anon()
        |> post(~p"/r/#{session.uuid}", %{
          name: "Greta Guest",
          answers: %{ids["Phone"] => "12", ids["Days"] => ["Thursday"]}
        })
        |> html_response(422)

      assert html =~ "Fill this in."
      assert html =~ "Enter a phone number"
      assert html =~ ~s(value="Greta Guest")
      assert html =~ ~s(value="12")
      assert html =~ ~r/value="Thursday"\s+checked/
      refute_received :engine_signup
      assert Repo.all(Link) == []
      assert_no_email_sent()

      # name and answers are checked together
      both =
        conn
        |> anon()
        |> post(~p"/r/#{session.uuid}", %{name: " ", answers: %{}})
        |> html_response(422)

      assert both =~ "Enter a name."
      assert both =~ "Fill this in."
    end

    test "answers are kept on the guest's link and the personal link is e-mailed",
         %{conn: conn, club: club} do
      {club, ids} = with_form(club)
      session = session_fixture(club, engine_event_id: 11, scheduled_at: ~U[2026-11-05 18:30:00Z])
      stub_stage([])

      html =
        conn
        |> anon()
        |> post(~p"/r/#{session.uuid}", %{
          name: "Greta Guest",
          answers: %{
            "email" => " greta@example.com ",
            ids["Phone"] => "+380 44 123 45 67",
            ids["Days"] => ["Thursday", "Monday"]
          }
        })
        |> html_response(200)

      assert [%Link{} = link] = Repo.all(Link)

      assert Enum.map(link.answers, &{&1["label"], &1["type"], &1["value"]}) == [
               {"Your e-mail", "email", "greta@example.com"},
               {"Phone", "phone", "+380 44 123 45 67"},
               {"First time?", "yesno", false},
               {"Days", "multi", ["Monday", "Thursday"]}
             ]

      assert html =~ "/l/#{link.code}"
      assert html =~ "We also sent it to greta@example.com."

      assert_email_sent(fn email ->
        assert email.to == [{"", "greta@example.com"}]
        assert email.subject == "Your link to Guest night"
        assert email.text_body =~ "Hello Greta Guest"

        assert email.text_body =~
                 "registered for Guest night at #{club.name}. The session is on 2026-11-05."

        assert email.text_body =~ "/l/#{link.code}"
      end)

      # a later form edit never changes what was answered
      {:ok, _club} =
        Cab.Clubs.edit_registration_form(club, &Core.Forms.remove_field(&1, ids["Phone"]))

      assert Enum.any?(Repo.reload!(link).answers, &(&1["label"] == "Phone"))
    end

    test "the e-mail speaks the request's language", %{conn: conn, club: club} do
      {club, _ids} = with_form(club)
      session = session_fixture(club, engine_event_id: 11)
      stub_stage([])

      conn
      |> anon()
      |> put_req_header("accept-language", "uk-UA,uk;q=0.9")
      |> post(~p"/r/#{session.uuid}", %{
        name: "Greta",
        answers: %{"email" => "g@example.com"}
      })
      |> html_response(200)

      assert_email_sent(fn email ->
        assert email.to == [{"", "g@example.com"}]
        refute email.subject =~ "Your link to"
        assert email.subject =~ "Guest night"
      end)
    end

    test "every club asks the e-mail; made optional and left empty, no e-mail",
         %{conn: conn, club: club} do
      session = session_fixture(club, engine_event_id: 11)
      stub_stage([])

      refused =
        conn |> anon() |> post(~p"/r/#{session.uuid}", %{name: "Greta"}) |> html_response(422)

      assert refused =~ "Your e-mail"
      assert refused =~ "Fill this in."

      {:ok, _club} =
        Cab.Clubs.edit_registration_form(
          club,
          &Core.Forms.update_field(&1, "email", %{"required" => "no"})
        )

      html =
        conn |> anon() |> post(~p"/r/#{session.uuid}", %{name: "Greta"}) |> html_response(200)

      refute html =~ "We also sent it"
      assert [%Link{answers: []}] = Repo.all(Link)
      assert_no_email_sent()
    end
  end

  # ---------------------------------------------------------------
  # Who sees the answers
  # ---------------------------------------------------------------

  describe "visibility" do
    setup %{club: club} do
      {club, ids} = with_form(club)
      session = session_fixture(club, engine_event_id: 11)
      guest = user_fixture(%{node_user_id: nil, name: "Greta Guest", username: "guest-greta"})
      link = link_fixture(guest, session, participant_id: 41)

      {:ok, answers} =
        Core.Forms.validate_answers(Cab.Clubs.guest_form(club), %{
          "email" => "greta@example.com",
          ids["Phone"] => "+380 50 765 43 21"
        })

      link = link |> Ecto.Changeset.change(answers: answers) |> Repo.update!()

      stub_stage([
        %{"id" => 41, "user_id" => nil, "role" => "speaker", "display_name" => "Greta Guest"}
      ])

      %{club: club, session: session, link: link}
    end

    test "the head sees them on the session's People list and in the links API",
         %{conn: conn, club: club, session: session, head: head} do
      html =
        conn
        |> log_in(head)
        |> get(~p"/c/#{club.uuid}/owner/s/#{session.uuid}")
        |> html_response(200)

      assert html =~ "greta@example.com"
      assert html =~ ~s(href="tel:+380507654321")

      body =
        conn
        |> log_in(head)
        |> get(~p"/api/cab/v1/sessions/#{session.uuid}/links")
        |> json_response(200)

      assert [%{"answers" => [email, phone, first_time]}] = body["links"]

      assert email == %{
               "id" => email["id"],
               "label" => "Your e-mail",
               "type" => "email",
               "value" => "greta@example.com"
             }

      assert phone["value"] == "+380 50 765 43 21"
      assert first_time["value"] == false

      form =
        conn
        |> log_in(head)
        |> get(~p"/api/cab/v1/clubs/#{club.uuid}/registration-form")
        |> json_response(200)

      assert Enum.map(form["fields"], & &1["label"]) == [
               "Your e-mail",
               "Phone",
               "First time?",
               "Days"
             ]
    end

    test "members, the public and the guest never see them",
         %{conn: conn, club: club, session: session, member: member, link: link} do
      pages = [
        ~p"/c/#{club.uuid}/s/#{session.uuid}",
        ~p"/c/#{club.uuid}",
        ~p"/r/#{session.uuid}"
      ]

      for path <- pages, who <- [:anon, member] do
        conn = if who == :anon, do: conn, else: log_in(conn, member)
        html = conn |> get(path) |> html_response(200)
        refute html =~ "greta@example.com", "#{path} shows an answer"
        refute html =~ "765 43 21", "#{path} shows an answer"
      end

      # the guest's own session page through their personal link
      guest_conn = get(conn, ~p"/l/#{link.code}")
      own = guest_conn |> get(~p"/c/#{club.uuid}/s/#{session.uuid}") |> html_response(200)
      refute own =~ "greta@example.com"

      for path <- [
            ~p"/api/cab/v1/sessions/#{session.uuid}",
            ~p"/api/cab/v1/clubs/#{club.uuid}",
            ~p"/api/cab/v1/clubs"
          ] do
        body = conn |> log_in(member) |> get(path) |> response(200)
        refute body =~ "greta@example.com", "#{path} shows an answer"
        refute body =~ "guest_form"
      end

      assert conn
             |> log_in(member)
             |> get(~p"/api/cab/v1/sessions/#{session.uuid}/links")
             |> json_response(403)

      assert conn
             |> log_in(member)
             |> get(~p"/api/cab/v1/clubs/#{club.uuid}/registration-form")
             |> json_response(403)

      assert conn
             |> get(~p"/api/cab/v1/clubs/#{club.uuid}/registration-form")
             |> json_response(401)
    end
  end

  # ---------------------------------------------------------------
  # API twin of the editor
  # ---------------------------------------------------------------

  describe "registration form API" do
    defp api(conn, user), do: if(user, do: log_in(conn, user), else: conn)

    test "GET and PUT: 401 anonymous, 403 member, 404 unknown club",
         %{conn: conn, club: club, head: head, member: member} do
      path = ~p"/api/cab/v1/clubs/#{club.uuid}/registration-form"
      body = %{fields: [%{label: "Phone", type: "phone"}]}

      assert conn |> get(path) |> json_response(401)
      assert conn |> put(path, body) |> json_response(401)
      assert conn |> api(member) |> get(path) |> json_response(403)
      assert conn |> api(member) |> put(path, body) |> json_response(403)

      unknown = ~p"/api/cab/v1/clubs/#{Ecto.UUID.generate()}/registration-form"
      assert conn |> api(member) |> get(unknown) |> response(404)
      assert Repo.reload!(club).guest_form == []

      # every club reads with its built-in e-mail, even before any edit
      head_body = conn |> api(head) |> get(path) |> json_response(200)

      assert [%{"id" => "email", "type" => "email", "locked" => true, "required" => true}] =
               head_body["fields"]
    end

    test "PUT replaces the definition, keeping given ids; head and admin",
         %{conn: conn, club: club, head: head} do
      {club, ids} = with_form(club)
      path = ~p"/api/cab/v1/clubs/#{club.uuid}/registration-form"

      stored =
        conn
        |> api(head)
        |> put(path, %{
          fields: [
            %{
              id: "email",
              label: "ignored",
              type: "text",
              required: false,
              hint: "for your link"
            },
            %{id: ids["Days"], label: "Days", type: "multi", options: ["Mon", "Thu"]},
            %{label: "Level", type: "choice", options: "novice\nopen", required: true}
          ]
        })
        |> json_response(200)

      assert [email, days, level] = stored["fields"]

      assert %{"label" => "Your e-mail", "type" => "email", "required" => false} = email
      assert email["hint"] == "for your link"
      assert days["id"] == ids["Days"]
      assert days["options"] == ["Mon", "Thu"]
      assert is_binary(level["id"]) and level["id"] not in Map.values(ids)
      assert level["required"] == true
      assert Cab.Clubs.guest_form(Repo.reload!(club)) == stored["fields"]

      admin =
        user_fixture(%{node_user_id: 88})
        |> Ecto.Changeset.change(is_admin: true)
        |> Repo.update!()

      assert %{"fields" => [_, _, _]} = conn |> api(admin) |> get(path) |> json_response(200)

      assert %{"fields" => [%{"id" => "email"}]} =
               conn
               |> api(admin)
               |> put(path, %{fields: [%{id: "email", required: true}]})
               |> json_response(200)
    end

    test "PUT refuses an invalid definition with stable codes; nothing changes",
         %{conn: conn, club: club, head: head} do
      {club, _ids} = with_form(club)
      path = ~p"/api/cab/v1/clubs/#{club.uuid}/registration-form"

      body =
        conn
        |> api(head)
        |> put(path, %{
          fields: [
            %{id: "email", required: true},
            %{label: "", type: "text"},
            %{label: "Colour", type: "colour"},
            %{label: "Level", type: "choice", options: ["only"]}
          ]
        })
        |> json_response(422)

      assert body["details"]["fields"] == %{
               "1" => %{"label" => "required"},
               "2" => %{"type" => "invalid_type"},
               "3" => %{"options" => "options_count"}
             }

      dup =
        conn
        |> api(head)
        |> put(path, %{
          fields: [
            %{id: "email"},
            %{id: "a", label: "A", type: "text"},
            %{id: "a", label: "B", type: "text"}
          ]
        })
        |> json_response(422)

      assert dup["details"]["form"] == "duplicate_id"

      # the built-in e-mail is never removed nor moved
      removed = conn |> api(head) |> put(path, %{fields: []}) |> json_response(422)
      assert removed["details"]["form"] == "locked_removed"

      moved =
        conn
        |> api(head)
        |> put(path, %{fields: [%{label: "A", type: "text"}, %{id: "email"}]})
        |> json_response(422)

      assert moved["details"]["form"] == "locked_moved"

      assert conn |> api(head) |> put(path, %{fields: "x"}) |> json_response(422)
      assert length(Cab.Clubs.guest_form(Repo.reload!(club))) == 4
    end
  end
end
