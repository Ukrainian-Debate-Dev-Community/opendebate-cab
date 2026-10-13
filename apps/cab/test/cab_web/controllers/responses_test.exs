defmodule CabWeb.ResponsesTest do
  @moduledoc """
  A session's form responses: the head's Responses page (a table,
  cards on phones), its CSV download and the API twin. Head and admin
  only; built from cab's own rows, never the engine.
  """
  use CabWeb.ConnCase, async: true

  import Cab.Fixtures

  alias Cab.Repo

  defp log_in(conn, user), do: init_test_session(conn, %{user_id: user.id})

  defp answer(id, label, type, value),
    do: %{"id" => id, "label" => label, "type" => type, "value" => value}

  defp guest(session, name, answers, inserted_at) do
    guest = user_fixture(%{node_user_id: nil, name: name})

    guest
    |> link_fixture(session)
    |> Ecto.Changeset.change(answers: answers, inserted_at: inserted_at)
    |> Repo.update!()
  end

  setup %{conn: conn} do
    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{name: "Kyivskyi klub"})

    # the form today: the built-in e-mail, then Phone and Level; an
    # older form asked "School", and "Level" was once "Your level"
    club =
      club
      |> Ecto.Changeset.change(
        guest_form: [
          %{"id" => "ph", "type" => "phone", "label" => "Phone", "required" => false},
          %{"id" => "lv", "type" => "choice", "label" => "Level", "required" => false}
        ]
      )
      |> Repo.update!()

    session =
      session_fixture(club, name: "Tuesday night", scheduled_at: ~U[2026-10-13 18:00:00Z])

    guest(
      session,
      ~s(Anna "Ann" Koval),
      [
        answer("email", "Your e-mail", "email", "anna@example.org"),
        answer("ph", "Phone", "phone", "+380 44 123 45 67"),
        answer("lv", "Level", "choice", "novice")
      ],
      ~U[2026-10-10 09:30:00Z]
    )

    guest(
      session,
      "Bohdan, Jr.",
      [
        answer("email", "Your e-mail", "email", "=HYPERLINK(\"http://x\")"),
        answer("old", "School", "longtext", "Lyceum 1,\nKyiv"),
        answer("lv", "Your level", "choice", "pro")
      ],
      ~U[2026-10-11 10:00:00Z]
    )

    # nothing on these pages may call the engine
    Req.Test.stub(Core.Engine, fn _conn -> raise "responses must not call the engine" end)

    %{conn: conn, head: head, club: club, session: session}
  end

  test "the head sees one row per guest, one column per field, old labels last",
       %{conn: conn, head: head, club: club, session: session} do
    html =
      conn
      |> log_in(head)
      |> get(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/responses")
      |> html_response(200)

    assert html =~ ~s(id="responses")
    assert html =~ ~s(class="t t-rows")

    # form order first, then labels only old answers carry
    headers = Regex.scan(~r/<th[^>]*>\s*([^<]*?)\s*<\/th>/, html, capture: :all_but_first)

    assert List.flatten(headers) ==
             ["Name", "Registered", "Your e-mail", "Phone", "Level", "School", "Your level"]

    # cells are labelled, so the table folds into cards on a phone
    assert html =~ ~s(data-label="School")
    assert html =~ "Anna &quot;Ann&quot; Koval"
    assert html =~ ~s(href="mailto:anna@example.org")
    assert html =~ "Lyceum 1,\nKyiv"
    assert html =~ ~s(datetime="2026-10-10T09:30:00Z")

    # the CSV link sits in the top bar, not gold
    csv = ~s(href="/c/#{club.uuid}/owner/sessions/#{session.uuid}/responses/csv")
    assert html =~ csv
    refute html =~ ~s(class="go")
  end

  test "the CSV: BOM, quoting, formulas kept as text, a named file",
       %{conn: conn, head: head, club: club, session: session} do
    conn =
      conn
      |> log_in(head)
      |> get(~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/responses/csv")

    body = response(conn, 200)
    assert ["text/csv; charset=utf-8"] = get_resp_header(conn, "content-type")
    assert ["no-store"] = get_resp_header(conn, "cache-control")

    assert [disposition] = get_resp_header(conn, "content-disposition")

    assert disposition ==
             ~s(attachment; filename="Kyivskyi klub - Tuesday night - 2026-10-13 - responses.csv"; ) <>
               "filename*=UTF-8''Kyivskyi%20klub%20-%20Tuesday%20night%20-%202026-10-13%20-%20responses.csv"

    assert <<0xEF, 0xBB, 0xBF, csv::binary>> = body

    assert csv ==
             "Name,Registered (UTC),Your e-mail,Phone,Level,School,Your level\r\n" <>
               ~s("Anna ""Ann"" Koval",2026-10-10 09:30,anna@example.org,+380 44 123 45 67,novice,,\r\n) <>
               ~s{"Bohdan, Jr.",2026-10-11 10:00,"'=HYPERLINK(""http://x"")",,,"Lyceum 1,\nKyiv",pro\r\n}
  end

  test "a Ukrainian file name keeps its letters in the UTF-8 name" do
    club = %{name: "\u041A\u0438\u0457\u0432: \u043A\u043B\u0443\u0431"}

    session = %{
      name: "\u0412\u0456\u0432\u0442\u043E\u0440\u043E\u043A",
      scheduled_at: nil,
      inserted_at: ~U[2026-10-13 18:00:00Z]
    }

    filename = CabWeb.ResponsesCsv.filename(club, session)

    assert filename ==
             "\u041A\u0438\u0457\u0432- \u043A\u043B\u0443\u0431 - " <>
               "\u0412\u0456\u0432\u0442\u043E\u0440\u043E\u043A - 2026-10-13 - responses.csv"

    disposition = CabWeb.ResponsesCsv.disposition(filename)
    assert disposition =~ ~s(filename="_- _ - _ - 2026-10-13 - responses.csv")
    assert disposition =~ "filename*=UTF-8''%D0%9A%D0%B8%D1%97%D0%B2-%20"
  end

  test "CSV fields: plain, quoted, doubled quotes, numbers and phones stay as they are" do
    import CabWeb.ResponsesCsv, only: [field: 1]

    assert field("plain") == "plain"
    assert field("a,b") == ~s("a,b")
    assert field(~s(say "hi")) == ~s("say ""hi""")
    assert field("two\r\nlines") == ~s("two\r\nlines")
    assert field(" padded") == ~s(" padded")
    assert field("+380 44 123 45 67") == "+380 44 123 45 67"
    assert field("-5") == "-5"
    assert field("=1+2") == "'=1+2"
    assert field("@SUM(A1)") == "'@SUM(A1)"
    assert field("-cmd") == "'-cmd"
    assert field(nil) == ""
  end

  test "the API twin returns the same rows", %{conn: conn, head: head, session: session} do
    data =
      conn
      |> log_in(head)
      |> get(~p"/api/cab/v1/sessions/#{session.uuid}/responses")
      |> json_response(200)

    assert data["uuid"] == session.uuid
    assert data["columns"] == ["Your e-mail", "Phone", "Level", "School", "Your level"]

    assert [anna, bohdan] = data["responses"]
    assert anna["name"] == ~s(Anna "Ann" Koval)
    assert anna["registered_at"] == "2026-10-10T09:30:00Z"

    assert anna["answers"] == %{
             "Your e-mail" => "anna@example.org",
             "Phone" => "+380 44 123 45 67",
             "Level" => "novice"
           }

    assert bohdan["answers"]["School"] == "Lyceum 1,\nKyiv"
  end

  test "head and admin only; another club's session is 404",
       %{conn: conn, club: club, session: session} do
    member = user_fixture()
    membership_fixture(member, club, status: "approved")

    admin =
      user_fixture()
      |> Ecto.Changeset.change(is_admin: true)
      |> Repo.update!()

    page = ~p"/c/#{club.uuid}/owner/sessions/#{session.uuid}/responses"
    csv = page <> "/csv"
    api = ~p"/api/cab/v1/sessions/#{session.uuid}/responses"

    for path <- [page, csv] do
      assert redirected_to(get(conn, path)) == "/signin"
      assert conn |> log_in(member) |> get(path) |> response(403)
      assert conn |> log_in(admin) |> get(path) |> response(200)
    end

    assert conn |> get(api) |> json_response(401)
    assert conn |> log_in(member) |> get(api) |> json_response(403)
    assert conn |> log_in(admin) |> get(api) |> json_response(200)

    # a session of another club through this club's URL
    other_head = user_fixture()
    other = club_fixture(other_head)
    foreign = session_fixture(other)

    assert conn
           |> log_in(other_head)
           |> get(~p"/c/#{other.uuid}/owner/sessions/#{session.uuid}/responses")
           |> response(404)

    assert conn
           |> log_in(other_head)
           |> get(~p"/c/#{other.uuid}/owner/sessions/#{foreign.uuid}/responses/csv")
           |> response(200)
  end
end
