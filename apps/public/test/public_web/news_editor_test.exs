defmodule PublicWeb.NewsEditorTest do
  @moduledoc """
  The news form writes the body in the rich text editor (ui's :rich
  block): the page names the editor's bundle, the block carries the
  image upload address, and images inside the text go to
  POST /manage/news/images - content managers only, the same checks as
  covers (by their bytes, up to 3 MB) - which answers JSON.
  """
  use PublicWeb.ConnCase

  alias Public.{News, Roles, Uploads}

  @png <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>> <> :binary.copy(<<0>>, 64)

  setup do
    File.rm_rf!(Uploads.dir())
    on_exit(fn -> File.rm_rf!(Uploads.dir()) end)
    :ok
  end

  defp editor do
    user = cab_user(%{name: "Iryna Editor"})
    {:ok, _} = Roles.grant(user.id)
    user
  end

  defp upload(bytes) do
    path = Path.join(System.tmp_dir!(), "editor-src-#{System.unique_integer([:positive])}")
    File.write!(path, bytes)
    on_exit(fn -> File.rm(path) end)
    %Plug.Upload{path: path, filename: "photo.png", content_type: "image/png"}
  end

  defp stored do
    case File.ls(Uploads.dir()) do
      {:ok, names} -> names
      {:error, :enoent} -> []
    end
  end

  test "the form's body is the rich text block, its bundle named on this page only",
       %{conn: conn} do
    html = conn |> cab_sign_in(editor()) |> get(~p"/manage/news/new") |> html_response(200)

    assert html =~ ~r{<meta[^>]* name="rich-editor-src" content="/assets/js/rich-editor.js"}
    assert html =~ ~s(data-rich)
    assert html =~ ~s(data-upload="/manage/news/images")

    for lang <- ~w(en uk) do
      assert html =~
               ~r{<textarea[^>]*class="rich-source"[^>]*name="post\[i18n\]\[#{lang}\]\[body\]"}
    end

    refute html =~ "Markdown"

    refute conn |> get(~p"/news") |> html_response(200) =~ "rich-editor"
  end

  test "a saved body is sanitised; the edit form shows it back", %{conn: conn} do
    signed = cab_sign_in(conn, editor())

    post(signed, ~p"/manage/news", %{
      "post" => %{
        "title" => "Sanitised",
        "body" =>
          ~s|<h2 style="x">Head</h2><p onclick="y()">Text <a href="javascript:z()">bad</a></p>| <>
            ~s(<img src="https://evil.example/a.png"><img src="/uploads/abc.png" alt="Ok"><p></p>)
      }
    })

    [post] = News.list_all()

    assert post.body ==
             ~s(<h2>Head</h2><p>Text bad</p><img src="/uploads/abc.png" alt="Ok" />)

    html = signed |> get(~p"/manage/news/#{post.id}/edit") |> html_response(200)
    assert html =~ "&lt;h2&gt;Head&lt;/h2&gt;"
  end

  test "a content manager's image is stored and answered with its address", %{conn: conn} do
    resp =
      conn
      |> cab_sign_in(editor())
      |> post(~p"/manage/news/images", %{"image" => upload(@png)})

    assert %{"url" => "/uploads/" <> name} = json_response(resp, 200)
    assert name =~ ~r/^[A-Za-z0-9_-]{24}\.png$/
    assert stored() == [name]
    assert response(get(conn, "/uploads/" <> name), 200) == @png
  end

  test "anything but an image, or over 3 MB, or no file, is refused as JSON",
       %{conn: conn} do
    signed = cab_sign_in(conn, editor())

    resp = post(signed, ~p"/manage/news/images", %{"image" => upload("GIF89a not a png")})
    assert json_response(resp, 422) == %{"error" => "Only JPEG, PNG or WebP images."}

    big = binary_part(@png, 0, 8) <> :binary.copy(<<0>>, Uploads.max_bytes())
    resp = post(signed, ~p"/manage/news/images", %{"image" => upload(big)})
    assert json_response(resp, 413) == %{"error" => "The image is larger than 3 MB."}

    resp = post(signed, ~p"/manage/news/images", %{})
    assert json_response(resp, 422) == %{"error" => "Only JPEG, PNG or WebP images."}

    assert stored() == []

    # exactly 3 MB is fine
    exact = binary_part(big, 0, Uploads.max_bytes())
    resp = post(signed, ~p"/manage/news/images", %{"image" => upload(exact)})
    assert %{"url" => _} = json_response(resp, 200)
  end

  test "the upload is no one else's: 404 signed in without the role, sign-in signed out",
       %{conn: conn} do
    assert_error_sent 404, fn ->
      conn |> cab_sign_in(cab_user()) |> post(~p"/manage/news/images", %{"image" => upload(@png)})
    end

    assert_error_sent 404, fn ->
      post(conn, ~p"/manage/news/images", %{"image" => upload(@png)})
    end

    assert stored() == []
  end

  test "the upload asks for the CSRF token", %{conn: conn} do
    conn =
      conn
      |> cab_sign_in(editor())
      |> Plug.Conn.put_private(:plug_skip_csrf_protection, false)

    assert_raise Plug.CSRFProtection.InvalidCSRFTokenError, fn ->
      post(conn, ~p"/manage/news/images", %{"image" => upload(@png)})
    end

    assert stored() == []
  end
end
