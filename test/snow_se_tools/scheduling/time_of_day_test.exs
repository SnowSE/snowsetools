defmodule SnowSeTools.Scheduling.TimeOfDayTest do
  use ExUnit.Case, async: true

  alias SnowSeTools.Scheduling.TimeOfDay

  describe "parse/1" do
    test "reads every clock shape Banner sends" do
      assert TimeOfDay.parse("09:30") == {:ok, 570}
      assert TimeOfDay.parse("09:30:00") == {:ok, 570}
      assert TimeOfDay.parse(" 09:30 ") == {:ok, 570}
      assert TimeOfDay.parse("00:00") == {:ok, 0}
      assert TimeOfDay.parse("23:59") == {:ok, 1439}
    end

    # The bug this module exists to kill: a single-digit hour used to be 540
    # minutes in the conflict detector, nil in the change manager and midnight
    # on the week grid.
    test "a single-digit hour is nine in the morning, not midnight" do
      assert TimeOfDay.parse("9:00") == {:ok, 540}
      assert TimeOfDay.parse("9:05:00") == {:ok, 545}
    end

    test "says so when a value is not a clock time" do
      for value <- ["", "later", "9", "9:", ":30", "25:00", "09:75", "ab:cd", nil, 540, %{}] do
        assert TimeOfDay.parse(value) == :error, "expected #{inspect(value)} to be unreadable"
      end
    end
  end

  describe "minutes/2" do
    test "falls back to the caller's default rather than a hidden one" do
      assert TimeOfDay.minutes("09:30", 0) == 570
      assert TimeOfDay.minutes("nonsense", 0) == 0
      assert TimeOfDay.minutes("nonsense", nil) == nil
      assert TimeOfDay.minutes(nil, 8 * 60) == 480
    end
  end

  describe "normalize/1 and normalize_or_nil/1" do
    test "different spellings of one time normalize to the same string" do
      assert TimeOfDay.normalize("9:00") == "09:00"
      assert TimeOfDay.normalize("09:00") == "09:00"
      assert TimeOfDay.normalize("09:00:00") == "09:00"
    end

    test "unreadable values collapse to the empty string or nil" do
      assert TimeOfDay.normalize("later") == ""
      assert TimeOfDay.normalize_or_nil("later") == nil
      assert TimeOfDay.normalize_or_nil(nil) == nil
    end
  end

  describe "format/1 and format_12h/1" do
    test "pads to a two-digit clock" do
      assert TimeOfDay.format(570) == "09:30"
      assert TimeOfDay.format(0) == "00:00"
      assert TimeOfDay.format(1439) == "23:59"
    end

    test "reads back as a twelve-hour time" do
      assert TimeOfDay.format_12h(0) == "12:00 AM"
      assert TimeOfDay.format_12h(570) == "9:30 AM"
      assert TimeOfDay.format_12h(720) == "12:00 PM"
      assert TimeOfDay.format_12h(1_290) == "9:30 PM"
    end

    test "round-trips through parse" do
      for minutes <- [0, 1, 540, 570, 719, 720, 1439] do
        assert TimeOfDay.parse(TimeOfDay.format(minutes)) == {:ok, minutes}
      end
    end
  end

  describe "duration/2" do
    test "measures the gap, and refuses when either end is unreadable" do
      assert TimeOfDay.duration("09:00", "09:50") == 50
      assert TimeOfDay.duration("09:00:00", "10:30") == 90
      assert TimeOfDay.duration("09:00", "later") == nil
      assert TimeOfDay.duration(nil, "10:30") == nil
    end
  end

  describe "week_days/0" do
    test "is the teaching week in display order" do
      assert TimeOfDay.week_days() == [
               "Monday",
               "Tuesday",
               "Wednesday",
               "Thursday",
               "Friday"
             ]

      assert TimeOfDay.week_day?("Monday")
      refute TimeOfDay.week_day?("Saturday")
    end
  end
end
