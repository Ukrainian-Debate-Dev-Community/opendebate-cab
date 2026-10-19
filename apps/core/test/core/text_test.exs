defmodule Core.TextTest do
  @moduledoc """
  Typed text: trimmed of whitespace and invisible characters, empty
  when nothing visible is left, control characters and over-long text
  refused.
  """
  use ExUnit.Case, async: true

  alias Core.Text

  describe "clean/2" do
    test "trims spaces, no-break spaces and invisible characters at the ends" do
      assert Text.clean("  Ann  ") == {:ok, "Ann"}
      assert Text.clean("\u00A0Ann\u00A0") == {:ok, "Ann"}
      assert Text.clean("\u200BAnn\u200C\u200D\uFEFF") == {:ok, "Ann"}
      assert Text.clean("\u2060\u00ADAnn\u3000") == {:ok, "Ann"}
    end

    test "keeps what is inside" do
      assert Text.clean("Ann\u00A0Lee") == {:ok, "Ann\u00A0Lee"}
      assert Text.clean("\u{1F469}\u200D\u{1F4BB}") == {:ok, "\u{1F469}\u200D\u{1F4BB}"}
    end

    test "nothing visible is empty: nil, or :required" do
      for blank <- [nil, "", "   ", "\u00A0\u00A0", "\u200B", "\uFEFF", " \u200C\u200D ", "\u2800", "\u3164", "\n\t"] do
        assert Text.clean(blank) == {:ok, nil}, inspect(blank)
        assert Text.clean(blank, required: true) == {:error, :required}, inspect(blank)
      end
    end

    test "counts characters, after trimming" do
      assert Text.clean(String.duplicate("a", 5), max: 5) == {:ok, "aaaaa"}
      assert Text.clean(" " <> String.duplicate("a", 5) <> "\u200B", max: 5) == {:ok, "aaaaa"}
      assert Text.clean(String.duplicate("\u0457", 5), max: 5) == {:ok, String.duplicate("\u0457", 5)}
      assert Text.clean(String.duplicate("a", 6), max: 5) == {:error, {:too_long, 5}}
    end

    test "refuses control characters in one-line text" do
      assert Text.clean("a\u0000b") == {:error, :invalid}
      assert Text.clean("a\u0007b") == {:error, :invalid}
      assert Text.clean("a\u007Fb") == {:error, :invalid}
      assert Text.clean("a\u0085b") == {:error, :invalid}
      assert Text.clean("a\nb") == {:error, :invalid}
      assert Text.clean("a\tb") == {:error, :invalid}
    end

    test "a long text keeps newlines and tabs, as LF" do
      assert Text.clean("\r\none\r\n\ttwo\rthree\n", multiline: true) == {:ok, "one\n\ttwo\nthree"}
      assert Text.clean("a\u0000b", multiline: true) == {:error, :invalid}
      assert Text.clean("a\u001Bb", multiline: true) == {:error, :invalid}
    end

    test "anything but UTF-8 text is invalid" do
      assert Text.clean(<<0xFF, 0xFE>>) == {:error, :invalid}
      assert Text.clean(["a"]) == {:error, :invalid}
      assert Text.clean(%{"a" => "b"}) == {:error, :invalid}
      assert Text.clean(12) == {:error, :invalid}
    end
  end

  describe "trim/1 and blank?/1" do
    test "trims the ends only" do
      assert Text.trim("\u200B ann@example.com\u00A0") == "ann@example.com"
      assert Text.trim(nil) == ""
      assert Text.trim(<<0xFF>>) == ""
    end

    test "blank when nothing visible is left" do
      assert Text.blank?(" \u00A0\u200B\uFEFF")
      assert Text.blank?(nil)
      refute Text.blank?(" a ")
    end
  end
end
