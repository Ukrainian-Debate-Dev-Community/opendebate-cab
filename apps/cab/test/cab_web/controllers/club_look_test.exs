defmodule CabWeb.ClubLookTest do
  @moduledoc """
  The club's logo: the head uploads it (PNG, JPEG or WebP by its bytes,
  at most 1 MB) on the club edit page; the club page, the directory
  and /r show it, the API carries logo_url, cab serves the file at
  /uploads.
  """
  use CabWeb.ConnCase, async: true

  import Cab.Fixtures

  alias Cab.Clubs
  alias Cab.Uploads

  @png <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 13, "IHDR">>
  @jpeg <<0xFF, 0xD8, 0xFF, 0xE0, 0, 16, "JFIF", 0>>
  @webp <<"RIFF", 26, 0, 0, 0, "WEBPVP8 ">>
  @svg ~s[<svg xmlns="http://www.w3.org/2000/svg"><script>alert(1)</script></svg>]

  setup do
    head = user_fixture()
    %{head: head, club: club_fixture(head, %{name: "Kyiv Debate Club", city: "Kyiv"})}
  end

  defp log_in(conn, user) do
    conn
    |> init_test_session(%{user_id: user.id})
    |> Plug.Conn.put_private(:plug_skip_csrf_protection, true)
  end

  defp tmp_file(bytes) do
    path = Path.join(System.tmp_dir!(), "logo-in-#{System.unique_integer([:positive])}")
    File.write!(path, bytes)
    on_exit(fn -> File.rm(path) end)
    path
  end

  defp upload(bytes, filename \\ "logo.png", type \\ "image/png"),
    do: %Plug.Upload{path: tmp_file(bytes), filename: filename, content_type: type}

  defp stored?(name), do: File.exists?(Path.join(Uploads.dir(), name))

  defp uploads_now do
    case File.ls(Uploads.dir()) do
      {:ok, names} -> MapSet.new(names)
      _ -> MapSet.new()
    end
  end

  defp img?(html, class, name),
    do: html =~ ~r/<img[^>]* class="#{class}" src="\/uploads\/#{Regex.escape(name)}" alt="">/

  defp with_logo(club, bytes \\ @png) do
    {:ok, club} = Clubs.update_club(club, %{}, {:file, tmp_file(bytes)})
    on_exit(fn -> Uploads.delete(club.logo) end)
    club
  end

  describe "Cab.Uploads" do
    test "takes PNG, JPEG and WebP by their bytes, whatever the name says" do
      for {bytes, ext} <- [{@png, ".png"}, {@jpeg, ".jpg"}, {@webp, ".webp"}] do
        assert {:ok, name} = Uploads.store(tmp_file(bytes))
        assert String.ends_with?(name, ext)
        assert stored?(name)
        Uploads.delete(name)
        refute stored?(name)
      end
    end

    test "refuses SVG, text, an empty file and anything over 1 MB, writing nothing" do
      before = uploads_now()

      assert Uploads.store(tmp_file(@svg)) == {:error, :type}
      assert Uploads.store(tmp_file("just text, named logo.png")) == {:error, :type}
      assert Uploads.store(tmp_file("")) == {:error, :type}

      big = @png <> :binary.copy(<<0>>, Uploads.max_bytes())
      assert Uploads.store(tmp_file(big)) == {:error, :size}
      assert {:ok, name} = Uploads.store(tmp_file(binary_part(big, 0, Uploads.max_bytes())))
      Uploads.delete(name)

      assert uploads_now() == before
    end

    test "random names, never the browser's" do
      {:ok, a} = Uploads.store(tmp_file(@png))
      {:ok, b} = Uploads.store(tmp_file(@png))
      assert a != b
      assert a =~ ~r/^[A-Za-z0-9_-]{24}\.png$/
      Uploads.delete(a)
      Uploads.delete(b)
    end
  end

  describe "logo upload" do
    test "the head uploads a logo; cab serves it with a long cache and nosniff", %{
      conn: conn,
      head: head,
      club: club
    } do
      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/club", %{name: club.name, logo: upload(@png)})

      %{logo: name} = Clubs.get_by_uuid(club.uuid)
      on_exit(fn -> Uploads.delete(name) end)
      assert name =~ ~r/\.png$/
      assert stored?(name)

      served = get(build_conn(), "/uploads/#{name}")
      assert response(served, 200) == File.read!(Path.join(Uploads.dir(), name))
      assert get_resp_header(served, "x-content-type-options") == ["nosniff"]
      assert get_resp_header(served, "cache-control") == ["public, max-age=31536000, immutable"]
      assert get_resp_header(served, "content-type") |> hd() =~ "image/png"

      html = conn |> log_in(head) |> get(~p"/c/#{club.uuid}/owner") |> html_response(200)
      assert html =~ ~s(src="/uploads/#{name}")
      assert html =~ ~s(name="remove_logo")
    end

    test "a new logo replaces the old file; removing deletes it", %{
      conn: conn,
      head: head,
      club: club
    } do
      old = with_logo(club).logo

      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/club", %{
        name: club.name,
        logo: upload(@webp, "x.webp", "image/webp")
      })

      new = Clubs.get_by_uuid(club.uuid).logo
      on_exit(fn -> Uploads.delete(new) end)
      assert new =~ ~r/\.webp$/
      refute stored?(old)
      assert stored?(new)

      # saving the profile without a file keeps the logo
      conn |> log_in(head) |> post(~p"/c/#{club.uuid}/owner/club", %{name: club.name})
      assert Clubs.get_by_uuid(club.uuid).logo == new

      conn
      |> log_in(head)
      |> post(~p"/c/#{club.uuid}/owner/club", %{name: club.name, remove_logo: "yes"})

      assert Clubs.get_by_uuid(club.uuid).logo == nil
      refute stored?(new)
    end

    test "a refused file writes nothing and saves nothing", %{conn: conn, head: head, club: club} do
      old = with_logo(club).logo
      before = uploads_now()

      for {file, message} <- [
            {upload(@svg, "logo.svg", "image/svg+xml"), "PNG, JPEG or WebP"},
            {upload("<html></html>", "logo.png", "image/png"), "PNG, JPEG or WebP"},
            {upload(@png <> :binary.copy(<<0>>, Uploads.max_bytes())), "1 MB"}
          ] do
        refused =
          conn
          |> log_in(head)
          |> post(~p"/c/#{club.uuid}/owner/club", %{name: club.name, city: "Lviv", logo: file})

        assert Phoenix.Flash.get(refused.assigns.flash, :error) =~ message
      end

      club = Clubs.get_by_uuid(club.uuid)
      assert club.logo == old
      assert club.city == "Kyiv"
      assert stored?(old)
      assert uploads_now() == before
    end

    test "only the head edits the logo", %{conn: conn, club: club} do
      stranger = user_fixture()

      conn
      |> log_in(stranger)
      |> post(~p"/c/#{club.uuid}/owner/club", %{name: club.name, logo: upload(@png)})

      assert Clubs.get_by_uuid(club.uuid).logo == nil
    end
  end

  describe "API" do
    test "the public profile carries an absolute logo_url", %{conn: conn, club: club} do
      body = conn |> get(~p"/api/cab/v1/clubs/#{club.uuid}") |> json_response(200)
      assert Map.has_key?(body, "logo_url")
      assert body["logo_url"] == nil

      club = with_logo(club)

      body = conn |> get(~p"/api/cab/v1/clubs/#{club.uuid}") |> json_response(200)
      assert body["logo_url"] == CabWeb.Endpoint.url() <> "/uploads/" <> club.logo
      assert body["logo_url"] =~ ~r{^https?://}

      %{"clubs" => clubs} = conn |> get(~p"/api/cab/v1/clubs") |> json_response(200)
      listed = Enum.find(clubs, &(&1["uuid"] == club.uuid))
      assert listed["logo_url"] == body["logo_url"]
    end

    test "PATCH cannot set the logo", %{conn: conn, head: head, club: club} do
      body =
        conn
        |> log_in(head)
        |> patch(~p"/api/cab/v1/clubs/#{club.uuid}", %{city: "Odesa", logo: "../../etc/passwd"})
        |> json_response(200)

      assert body["city"] == "Odesa"
      assert body["logo_url"] == nil
      assert Clubs.get_by_uuid(club.uuid).logo == nil
    end
  end

  describe "display" do
    test "without a logo the club page and the directory look as before", %{
      conn: conn,
      club: club
    } do
      page = conn |> get(~p"/c/#{club.uuid}") |> html_response(200)
      refute page =~ "club-logo"

      directory = conn |> get(~p"/") |> html_response(200)
      refute directory =~ "club-logo"
    end

    test "the club page and the directory show the logo", %{
      conn: conn,
      club: club
    } do
      club = with_logo(club)

      page = conn |> get(~p"/c/#{club.uuid}") |> html_response(200)
      assert img?(page, "club-logo lg", club.logo)

      directory = conn |> get(~p"/") |> html_response(200)
      assert img?(directory, "club-logo", club.logo)

      # the club's sidebar stays as it is
      refute page =~ ~r/<nav[^>]*sidenav.*?club-logo.*?<\/nav>/s
    end

    test "the registration page shows the club's logo", %{conn: conn, club: club} do
      session_fixture(club, engine_event_id: 11)
      stub_stage()

      html = conn |> get(~p"/c/#{club.uuid}") |> html_response(200)
      refute html =~ "club-logo"

      club = with_logo(club, @jpeg)

      html = conn |> get(~p"/c/#{club.uuid}") |> html_response(200)
      assert html =~ ~s(class="f-head with-logo")
      assert html =~ ~s(src="/uploads/#{club.logo}")
    end
  end

  defp stub_stage do
    ok = fn conn, data -> Req.Test.json(conn, %{"status" => "success", "data" => data}) end

    Req.Test.stub(Core.Engine, fn conn ->
      case {conn.method, conn.request_path} do
        {"GET", "/api/events/11"} ->
          ok.(conn, %{"id" => 11, "name" => "Guest night", "status" => "scheduled"})

        {"GET", "/api/events/11/rounds"} ->
          ok.(conn, [%{"id" => 21, "sequence" => 1}])

        {"GET", "/api/events/11/participants"} ->
          ok.(conn, [])

        {"GET", "/api/rounds/21/rooms"} ->
          ok.(conn, [])
      end
    end)
  end
end
