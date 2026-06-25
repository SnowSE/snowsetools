defmodule SnowSeToolsWeb.Scheduling.ScheduleOrderTest do
  use ExUnit.Case, async: true

  alias SnowSeToolsWeb.Scheduling.ScheduleOrder

  describe "new/1 and ordering helpers" do
    test "preserves insertion order and ignores duplicates" do
      order =
        ScheduleOrder.new(keys: ["a", "b", "a", "c"])

      assert ScheduleOrder.to_list(order) == ["a", "b", "c"]
      assert ScheduleOrder.size(order) == 3
      assert ScheduleOrder.member?(order: order, key: "b")
    end

    test "deletes keys and keeps the remaining order" do
      order =
        ScheduleOrder.new(keys: ["a", "b", "c"])
        |> then(&ScheduleOrder.delete(order: &1, key: "b"))

      assert ScheduleOrder.to_list(order) == ["a", "c"]
      refute ScheduleOrder.member?(order: order, key: "b")
    end

    test "moves a dragged key before the target key" do
      order =
        ScheduleOrder.new(keys: ["a", "b", "c", "d"])
        |> then(&ScheduleOrder.move_before(order: &1, dragged_key: "d", target_key: "b"))

      assert ScheduleOrder.to_list(order) == ["a", "d", "b", "c"]
    end

    test "moves a dragged key to the end when dropped on empty space" do
      order =
        ScheduleOrder.new(keys: ["a", "b", "c"])
        |> then(&ScheduleOrder.move_before(order: &1, dragged_key: "a", target_key: nil))

      assert ScheduleOrder.to_list(order) == ["b", "c", "a"]
    end

    test "retains only keys that still exist" do
      order =
        ScheduleOrder.new(keys: ["a", "b", "c"])
        |> then(&ScheduleOrder.retain_keys(order: &1, keys: MapSet.new(["c", "a"])))

      assert ScheduleOrder.to_list(order) == ["a", "c"]
    end
  end
end
