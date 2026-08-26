defmodule SnowSeToolsWeb.Scheduling.OverlayGroupTest do
  use SnowSeToolsWeb.ConnCase, async: true

  alias SnowSeTools.Scheduling.ScheduleUtils
  alias SnowSeToolsWeb.Scheduling.{OverlayGroup, WeekSchedule}

  test "renders each member's meetings in its own color with owner data for drag/edit" do
    week_schedules = %{
      "room:Hall 101" =>
        loaded("room:Hall 101", :room, "Hall 101", "50001", "Circuits", "09:00", "09:50"),
      "room:Hall 202" =>
        loaded("room:Hall 202", :room, "Hall 202", "50002", "Networks", "09:30", "10:20")
    }

    html =
      render_component(&OverlayGroup.render/1,
        group_key: "overlay:1",
        member_keys: ["room:Hall 101", "room:Hall 202"],
        week_schedules: week_schedules,
        position: 0,
        total_count: 1,
        overlay_targets: []
      )

    assert html =~ "Hall 101, Hall 202"
    assert html =~ "Overlay · 2 rooms"

    blocks =
      html
      |> LazyHTML.from_fragment()
      |> LazyHTML.query("[data-week-schedule-course]")

    assert LazyHTML.attribute(blocks, "data-owner-key") == ["room:Hall 101", "room:Hall 202"]

    [first_class, second_class] = LazyHTML.attribute(blocks, "class")
    assert first_class =~ "ring-sky-400"
    assert second_class =~ "ring-violet-400"

    # overlapping meetings from different members sit side by side
    [first_style, second_style] = LazyHTML.attribute(blocks, "style")
    assert first_style =~ "width: calc(50% - 2px)"
    assert second_style =~ "left: 50%"

    # pop-out control per member, separate control for the group
    assert html =~ "schedule-details-order:pop_out"
    assert html =~ "overlay-separate-overlay:1"
    # Add button hidden while there is nothing else of this kind to add
    refute html =~ "overlay-menu-overlay:1"
  end

  test "spans the union of member time ranges and tolerates a loading member" do
    week_schedules = %{
      "professor:A" => loaded("professor:A", :professor, "A", "50001", "Early", "07:30", "08:20"),
      "professor:B" => %WeekSchedule{owner_key: "professor:B", loading?: true, week_schedule: nil}
    }

    merged =
      OverlayGroup.merged_schedule(
        members: members(["professor:A", "professor:B"], week_schedules),
        type: :professor
      )

    assert merged.start_minutes == 7 * 60 + 30 or merged.start_minutes < 7 * 60 + 30
    assert merged.type == :professor
    assert length(merged.meetings_by_day["Monday"]) == 1
    assert hd(merged.meetings_by_day["Monday"]).overlay_owner_name == "A"
  end

  defp members(keys, week_schedules) do
    # exercise the public render path's member shaping through merged_schedule
    keys
    |> Enum.with_index()
    |> Enum.map(fn {key, index} ->
      state = week_schedules[key]
      schedule = state && state.week_schedule

      %{
        key: key,
        color: SnowSeToolsWeb.Scheduling.ScheduleOverlays.member_color(index),
        name: (schedule && schedule.name) || key,
        schedule: schedule,
        loading?: is_nil(schedule),
        selected_term_code: "202601"
      }
    end)
  end

  defp loaded(owner_key, type, name, crn, course_name, start_time, end_time) do
    week_schedule =
      ScheduleUtils.build_week_schedule(
        type: type,
        name: name,
        courses: [
          %{
            "crn" => crn,
            "subject_code" => "TEST",
            "course_number" => "1000",
            "name" => course_name,
            "credit_hours" => 3,
            "instructors" => [%{"name" => name}],
            "meet_info" => [
              %{
                "building" => "Hall",
                "building_code" => "H",
                "room" => String.replace(name, "Hall ", ""),
                "days" => ["Monday"],
                "start_time" => start_time <> ":00",
                "end_time" => end_time <> ":00"
              }
            ]
          }
        ]
      )
      |> Map.merge(%{program_name: nil, semester_name: nil, schedule_variants: []})

    %WeekSchedule{
      owner_key: owner_key,
      selected_term_code: "202601",
      course_list: nil,
      week_schedule: week_schedule,
      selected_variant_index: 0,
      loading?: false
    }
  end
end
