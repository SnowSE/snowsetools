defmodule SnowSeToolsWeb.Scheduling.ScheduleOverlaysTest do
  use ExUnit.Case, async: true

  alias SnowSeToolsWeb.Scheduling.{ScheduleOrder, ScheduleOverlays}

  describe "groups" do
    test "creates, extends and shrinks a group" do
      {group_key, overlays} =
        ScheduleOverlays.create(
          overlays: ScheduleOverlays.new(),
          owner_keys: ["room:A", "room:B"]
        )

      assert ScheduleOverlays.group_key?(group_key)
      refute ScheduleOverlays.group_key?("room:A")

      assert ScheduleOverlays.members(overlays: overlays, group_key: group_key) == [
               "room:A",
               "room:B"
             ]

      assert ScheduleOverlays.owner_group(overlays: overlays, owner_key: "room:B") == group_key
      assert ScheduleOverlays.owner_group(overlays: overlays, owner_key: "room:C") == nil

      overlays =
        ScheduleOverlays.add_member(overlays: overlays, group_key: group_key, owner_key: "room:C")

      assert ScheduleOverlays.all_owner_keys(overlays) == ["room:A", "room:B", "room:C"]

      overlays =
        ScheduleOverlays.remove_member(
          overlays: overlays,
          group_key: group_key,
          owner_key: "room:A"
        )

      assert ScheduleOverlays.members(overlays: overlays, group_key: group_key) == [
               "room:B",
               "room:C"
             ]
    end

    test "retain_owner_keys drops missing members and empty groups" do
      {g1, overlays} =
        ScheduleOverlays.create(
          overlays: ScheduleOverlays.new(),
          owner_keys: ["room:A", "room:B"]
        )

      {g2, overlays} = ScheduleOverlays.create(overlays: overlays, owner_keys: ["professor:X"])

      overlays = ScheduleOverlays.retain_owner_keys(overlays: overlays, keys: ["room:B"])

      assert ScheduleOverlays.members(overlays: overlays, group_key: g1) == ["room:B"]
      assert ScheduleOverlays.members(overlays: overlays, group_key: g2) == []
      assert ScheduleOverlays.group_keys(overlays) == [g1]
    end
  end

  describe "colors and kinds" do
    test "member colors cycle and never use the conflict/added/updated hues" do
      colors = Enum.map(0..7, &ScheduleOverlays.member_color/1)

      assert Enum.at(colors, 0) == Enum.at(colors, 6)

      for color <- colors do
        refute color.block =~ ~r/rose|emerald|amber/
      end
    end

    test "each kind has its own button color" do
      assert ScheduleOverlays.kind_style(:professor).button =~ "indigo"
      assert ScheduleOverlays.kind_style(:room).button =~ "teal"
      assert ScheduleOverlays.kind_label(type: :professor, count: 1) == "person"
      assert ScheduleOverlays.kind_label(type: :professor, count: 2) == "people"
      assert ScheduleOverlays.kind_label(type: :room, count: 3) == "rooms"
    end
  end

  describe "ScheduleOrder.put_before/put_after" do
    test "inserts relative to an anchor and moves an existing key" do
      order = ScheduleOrder.new(keys: ["a", "b", "c"])

      assert ScheduleOrder.to_list(ScheduleOrder.put_before(order, key: "x", before_key: "b")) ==
               ["a", "x", "b", "c"]

      assert ScheduleOrder.to_list(ScheduleOrder.put_after(order, key: "x", after_key: "b")) ==
               ["a", "b", "x", "c"]

      assert ScheduleOrder.to_list(ScheduleOrder.put_after(order, key: "x", after_key: "c")) ==
               ["a", "b", "c", "x"]

      assert ScheduleOrder.to_list(ScheduleOrder.put_after(order, key: "a", after_key: "c")) ==
               ["b", "c", "a"]

      assert ScheduleOrder.to_list(ScheduleOrder.put_after(order, key: "x", after_key: "missing")) ==
               ["a", "b", "c", "x"]
    end
  end
end
