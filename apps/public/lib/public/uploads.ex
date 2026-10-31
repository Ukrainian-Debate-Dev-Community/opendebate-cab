defmodule Public.Uploads do
  @moduledoc """
  News cover images on disk, in the :uploads_dir folder, served at
  /uploads. Only JPEG, PNG and WebP up to 3 MB, recognised by their
  first bytes, never by the name the browser sent; each file gets a
  random name. No resizing.
  """

  @max_bytes 3 * 1024 * 1024

  def dir, do: Application.fetch_env!(:public, :uploads_dir)

  def max_bytes, do: @max_bytes

  def url(name), do: "/uploads/" <> name

  @doc "Copies the file at `path` in; {:ok, name} or {:error, :type | :size}."
  def store(path) do
    with {:ok, %{size: size}} <- File.stat(path),
         :ok <- check_size(size),
         {:ok, ext} <- detect(path) do
      name = Base.url_encode64(:crypto.strong_rand_bytes(18), padding: false) <> ext
      File.mkdir_p!(dir())
      File.cp!(path, Path.join(dir(), name))
      {:ok, name}
    else
      {:error, reason} when reason in [:size, :type] -> {:error, reason}
      {:error, _} -> {:error, :type}
    end
  end

  def delete(nil), do: :ok

  def delete(name) do
    _ = File.rm(Path.join(dir(), Path.basename(name)))
    :ok
  end

  defp check_size(size) when size > 0 and size <= @max_bytes, do: :ok
  defp check_size(0), do: {:error, :type}
  defp check_size(_), do: {:error, :size}

  defp detect(path) do
    case File.open(path, [:read, :binary], &IO.binread(&1, 12)) do
      {:ok, <<0xFF, 0xD8, 0xFF, _::binary>>} -> {:ok, ".jpg"}
      {:ok, <<0x89, "PNG", 0x0D, 0x0A, 0x1A, 0x0A, _::binary>>} -> {:ok, ".png"}
      {:ok, <<"RIFF", _::binary-size(4), "WEBP">>} -> {:ok, ".webp"}
      _ -> {:error, :type}
    end
  end
end
