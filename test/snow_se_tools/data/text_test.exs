defmodule SnowSeTools.Data.TextTest do
  use ExUnit.Case, async: true

  alias SnowSeTools.Data.Text

  describe "blank?/1" do
    test "nil and whitespace are blank" do
      assert Text.blank?(nil)
      assert Text.blank?("")
      assert Text.blank?("   ")
      refute Text.blank?("x")
      refute Text.blank?(" x ")
    end

    test "a value that is not a string is something" do
      refute Text.blank?(0)
      refute Text.blank?(101)
      refute Text.blank?(%{})
    end
  end

  describe "blank_string?/1" do
    # The stricter reading: callers building a room name out of this must not
    # accept a room number that arrived as an integer, or they invent an owner
    # key nothing else in the system knows about.
    test "anything that is not a non-empty string is blank" do
      assert Text.blank_string?(nil)
      assert Text.blank_string?("")
      assert Text.blank_string?("  ")
      assert Text.blank_string?(101)
      assert Text.blank_string?(%{})
      refute Text.blank_string?("101")
    end
  end

  test "present? and present_string? are the negations" do
    assert Text.present?(101)
    refute Text.present_string?(101)
    assert Text.present_string?("101")
  end
end
