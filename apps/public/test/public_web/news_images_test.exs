defmodule PublicWeb.NewsImagesTest do
  @moduledoc """
  News cover images: taken by their first bytes, up to 3 MB, stored
  under a random name and served from /uploads; a replaced or removed
  file leaves the disk. Without one, the gradient stays.
  """
  use PublicWeb.ConnCase

  alias Public.{News, Roles, Uploads}

  @png <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A>> <> :binary.copy(<<0>>, 64)
  @jpeg <<0xFF, 0xD8, 0xFF, 0xE0>> <> :binary.copy(<<0>>, 64)
  @webp "RIFF" <> <<64, 0, 0, 0>> <> "WEBP" <> :binary.copy(<<0>>, 64)

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

  defp upload(filename, bytes) do
    path = Path.join(System.tmp_dir!(), "upload-src-#{System.unique_integer([:positive])}")
    File.write!(path, bytes)
    on_exit(fn -> File.rm(path) end)
    %Plug.Upload{path: path, filename: filename, content_type: "image/png"}
  end

  defp stored do
    case File.ls(Uploads.dir()) do
      {:ok, names} -> Enum.sort(names)
      {:error, :enoent} -> []
    end
  end

  test "a picture is taken by its bytes under a random name, shown, replaced and removed",
       %{conn: conn} do
    signed = cab_sign_in(conn, editor())

    post(signed, ~p"/manage/news", %{
      "post" => %{
        "title" => "Season opens",
        "image" => upload("photo.gif", @png),
        "image_alt" => "Debaters on stage"
      }
    })

    [post] = News.list_all()
    assert post.image =~ ~r/^[A-Za-z0-9_-]{24}\.png$/
    assert stored() == [post.image]
    {:ok, _} = News.publish(post, 1)

    for path <- [~p"/news", ~p"/news/season-opens", ~p"/"] do
      html = conn |> get(path) |> html_response(200)
      assert html =~ ~s(src="/uploads/#{post.image}"), path
      assert html =~ ~s(alt="Debaters on stage"), path
    end

    resp = get(conn, "/uploads/#{post.image}")
    assert response(resp, 200) == @png
    assert get_resp_header(resp, "cache-control") == ["public, max-age=31536000, immutable"]
    assert get_resp_header(resp, "set-cookie") == []

    put(signed, ~p"/manage/news/#{post.id}", %{
      "post" => %{"title" => "Season opens", "image" => upload("next.jpg", @jpeg)}
    })

    replaced = News.get!(post.id)
    assert replaced.image =~ ~r/\.jpg$/
    assert stored() == [replaced.image], "the replaced file is still on disk"

    put(signed, ~p"/manage/news/#{post.id}", %{
      "post" => %{"title" => "Season opens", "remove_image" => "true"}
    })

    assert News.get!(post.id).image == nil
    assert stored() == []

    html = conn |> get(~p"/news/season-opens") |> html_response(200)
    refute html =~ "/uploads/"
    assert html =~ ~r/class="ua-cover c[123] ua-cover--wide"/
  end

  test "without an image the card keeps its gradient", %{conn: conn} do
    {:ok, post} = News.create(%{"title" => "Plain"}, 1)
    {:ok, _} = News.publish(post, 1)

    html = conn |> get(~p"/news") |> html_response(200)
    assert html =~ ~r/class="ua-cover c[123]"/
    refute html =~ "ua-cover--img"
  end

  test "anything but JPEG, PNG or WebP, or over 3 MB, is refused", %{conn: conn} do
    signed = cab_sign_in(conn, editor())

    html =
      signed
      |> post(~p"/manage/news", %{
        "post" => %{"title" => "Fake", "image" => upload("fake.png", "GIF89a" <> "not a png")}
      })
      |> html_response(200)

    assert html =~ "Only JPEG, PNG or WebP images."

    big = binary_part(@png, 0, 8) <> :binary.copy(<<0>>, Uploads.max_bytes())

    html =
      signed
      |> post(~p"/manage/news", %{
        "post" => %{"title" => "Big", "image" => upload("big.png", big)}
      })
      |> html_response(200)

    assert html =~ "The image is larger than 3 MB."
    assert News.list_all() == []
    assert stored() == []

    assert {:ok, name} = Uploads.store(upload("a.webp", @webp).path)
    assert name =~ ~r/\.webp$/
    assert {:ok, _} = Uploads.store(upload("a", binary_part(big, 0, Uploads.max_bytes())).path)
  end

  test "a refused save keeps the old picture and drops the new file", %{conn: conn} do
    signed = cab_sign_in(conn, editor())
    {:ok, name} = Uploads.store(upload("a.png", @png).path)
    {:ok, post} = News.create(%{"title" => "Kept"}, 1, {:new, name})

    put(signed, ~p"/manage/news/#{post.id}", %{
      "post" => %{"title" => "", "image" => upload("b.jpg", @jpeg)}
    })

    assert News.get!(post.id).image == name
    assert stored() == [name]
  end
end
