defmodule CabWeb.BotGuardTest do
  @moduledoc """
  Bot protection on the public forms - a guest's registration at
  /r/:sess and a join request at /c/:club/join: Cloudflare Turnstile
  (widget and server-side check, Cloudflare stubbed with Req.Test).
  Signed-in members registering for a session are never asked.
  """
  # the settings are application-wide: this module runs alone
  use CabWeb.ConnCase, async: false

  import Cab.Fixtures
  import Swoosh.TestAssertions

  alias Cab.Links.Link
  alias Cab.Repo

  @site_key "1x00000000000000000000AA"
  @pass_secret "1x0000000000000000000000000000000AA"
  @fail_secret "2x0000000000000000000000000000000AA"
  @token "XXXX.DUMMY.TOKEN.XXXX"

  setup %{conn: conn} do
    turnstile = Application.get_env(:cab, :turnstile)
    on_exit(fn -> restore(:turnstile, turnstile) end)

    head = user_fixture(%{node_user_id: 9})
    club = club_fixture(head, %{engine_organisation_id: 3})
    member = user_fixture(%{node_user_id: 77})
    membership_fixture(member, club)
    session = session_fixture(club, engine_event_id: 11)
    stub_engine()

    %{conn: conn, head: head, club: club, member: member, session: session}
  end

  defp restore(key, nil), do: Application.delete_env(:cab, key)
  defp restore(key, value), do: Application.put_env(:cab, key, value)

  # Cloudflare's test keys; `verdict` answers siteverify
  defp turnstile_on(secret \\ @pass_secret, verdict \\ :by_secret) do
    Application.put_env(:cab, :turnstile,
      site_key: @site_key,
      secret_key: secret,
      req_options: [plug: {Req.Test, CabWeb.Turnstile}]
    )

    test_pid = self()

    Req.Test.stub(CabWeb.Turnstile, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      form = URI.decode_query(body)
      send(test_pid, {:siteverify, form})

      case verdict do
        :by_secret ->
          success = form["secret"] == @pass_secret and form["response"] == @token
          Req.Test.json(conn, %{"success" => success, "error-codes" => []})

        :down ->
          Req.Test.transport_error(conn, :econnrefused)

        :error_500 ->
          conn |> Plug.Conn.put_status(500) |> Req.Test.json(%{})
      end
    end)
  end

  defp ok(conn, data), do: Req.Test.json(conn, %{"status" => "success", "data" => data})

  defp stub_engine do
    Req.Test.stub(Core.Engine, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/11"} ->
          ok(conn, %{"id" => 11, "name" => "Guest night", "status" => "scheduled"})

        {"GET", "/api/events/11/rounds"} ->
          ok(conn, [%{"id" => 21, "sequence" => 1}])

        {"GET", "/api/events/11/participants"} ->
          ok(conn, [])

        {"GET", "/api/rounds/21/rooms"} ->
          ok(conn, [])

        {"POST", "/api/events/11/participants"} ->
          ok(conn, %{"id" => 41, "role" => "speaker", "raw_claim_token" => "tok-41"})

        {"PUT", "/api/events/11/participants/" <> _id} ->
          ok(conn, %{})
      end
    end)
  end

  defp anon(conn), do: Plug.Conn.put_private(conn, :plug_skip_csrf_protection, true)

  defp log_in(conn, user) do
    conn
    |> init_test_session(%{user_id: user.id})
    |> Plug.Conn.put_private(:plug_skip_csrf_protection, true)
  end

  defp guest(extra \\ %{}),
    do:
      Map.merge(%{"name" => "Greta Guest", "answers" => %{"email" => "greta@example.com"}}, extra)

  defp join(extra),
    do: Map.merge(%{"message" => "I debated at school", "contact" => "@wb"}, extra)

  describe "Turnstile widget" do
    test "off without keys: no widget, no script", %{conn: conn, club: club, session: session} do
      html = conn |> get(~p"/r/#{session.uuid}") |> html_response(200)
      refute html =~ "cf-turnstile"
      refute html =~ "challenges.cloudflare.com"

      user = user_fixture()
      join_html = conn |> log_in(user) |> get(~p"/c/#{club.uuid}/join") |> html_response(200)
      refute join_html =~ "cf-turnstile"
    end

    test "on: the guest form and the join form carry it, in the page's language",
         %{conn: conn, club: club, session: session} do
      turnstile_on()

      html = conn |> get(~p"/r/#{session.uuid}") |> html_response(200)
      assert html =~ ~s(class="cf-turnstile")
      assert html =~ ~s(data-sitekey="#{@site_key}")
      assert html =~ ~s(data-language="en")
      assert html =~ ~s(data-theme="auto")
      assert html =~ ~s(src="https://challenges.cloudflare.com/turnstile/v0/api.js")

      uk =
        conn
        |> put_req_header("accept-language", "uk")
        |> get(~p"/r/#{session.uuid}")
        |> html_response(200)

      assert uk =~ ~s(data-language="uk")

      user = user_fixture()
      join_html = conn |> log_in(user) |> get(~p"/c/#{club.uuid}/join") |> html_response(200)
      assert join_html =~ ~s(data-sitekey="#{@site_key}")
    end

    test "never for a signed-in member or on the head's preview",
         %{conn: conn, head: head, club: club, member: member, session: session} do
      turnstile_on()

      html = conn |> log_in(member) |> get(~p"/r/#{session.uuid}") |> html_response(200)
      refute html =~ "cf-turnstile"

      preview =
        conn |> log_in(head) |> get(~p"/c/#{club.uuid}/owner/form/preview")

      refute html_response(preview, 200) =~ "cf-turnstile"
    end
  end

  describe "Turnstile check" do
    test "a passing token registers the guest; Cloudflare gets the secret and the IP",
         %{conn: conn, session: session} do
      turnstile_on()

      html =
        conn
        |> anon()
        |> post(~p"/r/#{session.uuid}", guest(%{"cf-turnstile-response" => @token}))
        |> html_response(200)

      assert [%Link{} = link] = Repo.all(Link)
      assert html =~ "/l/#{link.code}"

      assert_received {:siteverify, form}
      assert form["secret"] == @pass_secret
      assert form["response"] == @token
      assert form["remoteip"] == "127.0.0.1"
    end

    test "a failing or missing token re-renders the form; nothing is created",
         %{conn: conn, session: session} do
      turnstile_on(@fail_secret)

      html =
        conn
        |> anon()
        |> post(~p"/r/#{session.uuid}", guest(%{"cf-turnstile-response" => @token}))
        |> html_response(422)

      assert html =~ "Please confirm you are not a robot."
      assert html =~ ~s(value="Greta Guest")
      assert_received {:siteverify, _form}

      missing = conn |> anon() |> post(~p"/r/#{session.uuid}", guest()) |> html_response(422)
      assert missing =~ "Please confirm you are not a robot."
      refute_received {:siteverify, _form}

      assert Repo.all(Link) == []
      assert_no_email_sent()
    end

    test "Cloudflare out of reach or failing refuses (fail closed)",
         %{conn: conn, session: session} do
      for verdict <- [:down, :error_500] do
        turnstile_on(@pass_secret, verdict)

        html =
          conn
          |> anon()
          |> post(~p"/r/#{session.uuid}", guest(%{"cf-turnstile-response" => @token}))
          |> html_response(422)

        assert html =~ "We could not check that you are not a robot right now."
      end

      assert Repo.all(Link) == []
    end

    test "the client IP is CF-Connecting-IP when the limiter trusts Cloudflare",
         %{conn: conn, session: session} do
      turnstile_on()
      rate_limit = Application.get_env(:cab, CabWeb.RateLimit)
      on_exit(fn -> Application.put_env(:cab, CabWeb.RateLimit, rate_limit) end)
      Application.put_env(:cab, CabWeb.RateLimit, Keyword.put(rate_limit, :trust_cf_ip, true))

      conn
      |> anon()
      |> put_req_header("cf-connecting-ip", "203.0.113.7")
      |> post(~p"/r/#{session.uuid}", guest(%{"cf-turnstile-response" => @token}))
      |> html_response(200)

      assert_received {:siteverify, %{"remoteip" => "203.0.113.7"}}
    end

    test "a signed-in member registers without a token",
         %{conn: conn, club: club, member: member, session: session} do
      turnstile_on(@fail_secret)

      registered = conn |> log_in(member) |> post(~p"/r/#{session.uuid}", %{})
      assert redirected_to(registered) == "/c/#{club.uuid}/s/#{session.uuid}"
      assert Phoenix.Flash.get(registered.assigns.flash, :info) == "You are registered."
      refute_received {:siteverify, _form}
    end

    test "a join request is checked the same way", %{conn: conn, club: club} do
      user = user_fixture()
      turnstile_on(@fail_secret)

      html =
        conn
        |> log_in(user)
        |> post(~p"/c/#{club.uuid}/join", join(%{"cf-turnstile-response" => @token}))
        |> html_response(422)

      assert html =~ "Please confirm you are not a robot."
      assert html =~ "I debated at school"
      assert Cab.Clubs.list_join_requests(club) == []

      turnstile_on()

      sent =
        conn
        |> log_in(user)
        |> post(~p"/c/#{club.uuid}/join", join(%{"cf-turnstile-response" => @token}))

      assert redirected_to(sent) == "/c/#{club.uuid}"
      assert [_request] = Cab.Clubs.list_join_requests(club)
    end
  end
end
