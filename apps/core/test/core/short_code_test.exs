defmodule Core.ShortCodeTest do
  use ExUnit.Case, async: true

  doctest Core.ShortCode

  test "codes are six characters, no look-alikes, always a digit" do
    for _ <- 1..500 do
      code = Core.ShortCode.generate()
      assert Core.ShortCode.code?(code), code
      refute code =~ ~r/[01ilo]/
    end
  end

  test "words and malformed segments are never codes" do
    for segment <- ["signin", "admin1", "abcdef", "abc23", "abcd234", "ABC234", "ab0c23", nil, 7] do
      refute Core.ShortCode.code?(segment), inspect(segment)
    end

    assert Core.ShortCode.code?("k7m2q9")
  end
end
