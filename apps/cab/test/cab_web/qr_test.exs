defmodule CabWeb.QRTest do
  use ExUnit.Case, async: true

  alias CabWeb.QR

  # reference matrices from the python `qrcode` library (byte mode,
  # level M), one per text and mask: version 1, version 3 and version 7
  # (which carries the version information blocks)
  @reference "test/fixtures/qr_reference.json" |> File.read!() |> Jason.decode!()

  defp bits(matrix),
    do: Enum.map(matrix, fn row -> Enum.map_join(row, &if(&1, do: "1", else: "0")) end)

  for %{"text" => text, "mask" => mask, "version" => version} = ref <- @reference do
    @ref ref
    test "matches the reference for version #{version}, mask #{mask}: #{String.slice(text, 0, 24)}" do
      assert bits(QR.matrix(@ref["text"], @ref["mask"])) == @ref["rows"]
    end
  end

  test "picks the smallest version and returns a square matrix" do
    matrix = QR.matrix("https://cab.uadebate.com/k7m2q9/1")
    assert length(matrix) == 29
    assert Enum.all?(matrix, &(length(&1) == 29))
  end

  test "refuses text beyond version 10" do
    assert QR.matrix(String.duplicate("x", 300)) == {:error, :too_long}
  end
end
