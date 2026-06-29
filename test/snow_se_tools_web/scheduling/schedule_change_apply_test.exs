defmodule SnowSeToolsWeb.Scheduling.ScheduleChangeApplyTest do
  use ExUnit.Case, async: true

  alias SnowSeTools.Scheduling.ScheduleUtils
  alias SnowSeToolsWeb.Scheduling.ScheduleChangeApply

  describe "apply_changes" do
    test "returns original schedule when no changes" do
      course =
        build_course("10001", "Intro to CS", [
          build_meeting(["Monday", "Wednesday"], "09:00", "10:30", "Room 101")
        ])

      schedule = build_schedule_owner([course])
      group = build_change_group([])

      result = apply_changes_to_schedule(schedule, group["changes"])

      assert result.name == "CS:Fall2024"
      assert length(result.courses) == 1
      assert hd(result.courses)["crn"] == "10001"
    end

    test "update change preserves original course fields not in change" do
      course =
        build_course("10001", "Intro to CS", [
          build_meeting(["Monday", "Wednesday"], "09:00", "10:30", "Room 101")
        ])

      schedule = build_schedule_owner([course])

      change =
        build_update_change("10001", "Intro to CS", [
          build_meeting(["Tuesday", "Thursday"], "11:00", "12:30", "Room 202")
        ])

      result = ScheduleChangeApply.apply_changes(schedule, [change])

      assert length(result.courses) == 1
      updated = hd(result.courses)
      assert updated["crn"] == "10001"
      assert updated["name"] == "Intro to CS"
      assert hd(updated["meet_info"])["room"] == "Room 202"
    end

    test "update change preserves original meet_info when change has nil meet_info" do
      original_meetings = [
        build_meeting(["Monday", "Wednesday"], "09:00", "10:30", "Room 101")
      ]

      course = build_course("10001", "Intro to CS", original_meetings)
      schedule = build_schedule_owner([course])

      change = build_update_change("10001", "Intro to CS", nil, "Dr. Jones")
      result = ScheduleChangeApply.apply_changes(schedule, [change])

      assert length(result.courses) == 1
      updated = hd(result.courses)
      assert length(updated["meet_info"]) == 1
      assert hd(updated["meet_info"])["room"] == "Room 101"
      assert hd(updated["meet_info"])["start_minutes"] == 540
    end

    test "add change creates a new course entry" do
      course =
        build_course("10001", "Intro to CS", [
          build_meeting(["Monday", "Wednesday"], "09:00", "10:30", "Room 101")
        ])

      schedule = build_schedule_owner([course])

      change =
        build_add_change("20001", "New Course", [
          build_meeting(["Tuesday", "Thursday"], "14:00", "15:30", "Room 303")
        ])

      result = ScheduleChangeApply.apply_changes(schedule, [change])

      assert length(result.courses) == 2
      new_course = Enum.find(result.courses, &(&1["crn"] == "20001"))
      assert new_course["name"] == "New Course"
    end

    test "multiple changes apply correctly together" do
      courses = [
        build_course("10001", "Intro to CS", [
          build_meeting(["Monday", "Wednesday"], "09:00", "10:30", "Room 101")
        ]),
        build_course("10002", "Data Structures", [
          build_meeting(["Tuesday", "Thursday"], "11:00", "12:30", "Room 102")
        ])
      ]

      schedule = build_schedule_owner(courses)

      changes = [
        build_update_change("10001", "Intro to CS", [
          build_meeting(["Monday", "Wednesday"], "10:00", "11:30", "Room 105")
        ]),
        build_add_change("30001", "Algorithms", [
          build_meeting(["Friday"], "09:00", "12:00", "Room 201")
        ])
      ]

      group = build_change_group(changes)
      result = apply_changes_to_schedule(schedule, group["changes"])

      assert length(result.courses) == 3

      updated =
        Enum.find(result.courses, &(&1["crn"] == "10001"))

      assert hd(updated["meet_info"])["room"] == "Room 105"

      new =
        Enum.find(result.courses, &(&1["crn"] == "30001"))

      assert new["name"] == "Algorithms"
    end

    test "update with professor change updates instructors" do
      course =
        build_course("10001", "Intro to CS", [
          build_meeting(["Monday", "Wednesday"], "09:00", "10:30", "Room 101")
        ])

      schedule = build_schedule_owner([course])

      change = build_update_change("10001", "Intro to CS", nil, "Dr. New Professor")
      result = ScheduleChangeApply.apply_changes(schedule, [change])

      updated = hd(result.courses)
      assert hd(updated["instructors"])["name"] == "Dr. New Professor"
    end

    test "update with nil professor preserves original instructors" do
      course =
        build_course("10001", "Intro to CS", [
          build_meeting(["Monday", "Wednesday"], "09:00", "10:30", "Room 101")
        ])

      schedule = build_schedule_owner([course])

      change = build_update_change("10001", "Intro to CS", nil, nil)
      group = build_change_group([change])
      result = apply_changes_to_schedule(schedule, group["changes"])

      updated = hd(result.courses)
      assert hd(updated["instructors"])["name"] == "Dr. Smith"
    end

    test "room schedule removes an updated course moved to another room" do
      course =
        build_course("10001", "Intro to CS", [
          build_meeting(["Monday"], "09:00", "10:30", "Room 101")
        ])

      schedule = build_schedule_owner([course], :room, "Room 101")

      change =
        build_update_change("10001", "Intro to CS", [
          build_meeting(["Monday"], "09:00", "10:30", "Room 202")
        ])

      result = ScheduleChangeApply.apply_changes(schedule, [change])

      assert result.courses == []
      assert Map.get(result.meetings_by_day, "Monday") == []
    end

    test "room schedule shows an updated course moved into the room" do
      schedule = build_schedule_owner([], :room, "Room 202")

      change =
        build_update_change("10001", "Intro to CS", [
          build_meeting(["Monday"], "09:00", "10:30", "Room 202")
        ])

      result = ScheduleChangeApply.apply_changes(schedule, [change])

      assert length(result.courses) == 1
      assert hd(result.courses)["crn"] == "10001"
      assert length(Map.get(result.meetings_by_day, "Monday")) == 1
    end

    test "professor schedule removes an updated course reassigned to another professor" do
      course =
        build_course("10001", "Intro to CS", [
          build_meeting(["Monday"], "09:00", "10:30", "Room 101")
        ])

      schedule = build_schedule_owner([course], :professor, "Dr. Smith")
      change = build_update_change("10001", "Intro to CS", nil, "Dr. Jones")

      result = ScheduleChangeApply.apply_changes(schedule, [change])

      assert result.courses == []
      assert Map.get(result.meetings_by_day, "Monday") == []
    end
  end

  describe "meetings_by_day after applying changes" do
    test "rebuilt schedule has correct meetings_by_day structure" do
      course =
        build_course("10001", "Intro to CS", [
          build_meeting(["Monday", "Wednesday"], "09:00", "10:30", "Room 101")
        ])

      schedule = build_schedule_owner([course])
      assert length(Map.get(schedule.meetings_by_day, "Monday")) == 1
      assert length(Map.get(schedule.meetings_by_day, "Wednesday")) == 1
      assert length(Map.get(schedule.meetings_by_day, "Tuesday")) == 0
    end

    test "update change reflects in meetings_by_day" do
      course =
        build_course("10001", "Intro to CS", [
          build_meeting(["Monday", "Wednesday"], "09:00", "10:30", "Room 101")
        ])

      schedule = build_schedule_owner([course])

      change =
        build_update_change("10001", "Intro to CS", [
          build_meeting(["Tuesday", "Thursday"], "11:00", "12:30", "Room 202")
        ])

      group = build_change_group([change])
      result = apply_changes_to_schedule(schedule, group["changes"])

      assert length(Map.get(result.meetings_by_day, "Monday")) == 0
      assert length(Map.get(result.meetings_by_day, "Wednesday")) == 0
      assert length(Map.get(result.meetings_by_day, "Tuesday")) == 1
      assert length(Map.get(result.meetings_by_day, "Thursday")) == 1
    end

    test "add change appears in meetings_by_day" do
      course =
        build_course("10001", "Intro to CS", [
          build_meeting(["Monday", "Wednesday"], "09:00", "10:30", "Room 101")
        ])

      schedule = build_schedule_owner([course])

      change =
        build_add_change("20001", "New Course", [
          build_meeting(["Friday"], "14:00", "15:30", "Room 303")
        ])

      group = build_change_group([change])
      result = apply_changes_to_schedule(schedule, group["changes"])

      friday_meetings = Map.get(result.meetings_by_day, "Friday")
      assert length(friday_meetings) == 1
      assert hd(friday_meetings).room == "Room 303"
    end

    test "meeting has all required fields for grid rendering" do
      course =
        build_course("10001", "Intro to CS", [
          build_meeting(["Monday"], "09:00", "10:30", "Room 101")
        ])

      schedule = build_schedule_owner([course])

      monday_meetings = Map.get(schedule.meetings_by_day, "Monday")
      assert length(monday_meetings) == 1

      meeting = hd(monday_meetings)
      assert meeting.course_name == "Intro to CS"
      assert meeting.subject_code == "CS"
      assert meeting.course_number == "101"
      assert meeting.crn == "10001"
      assert meeting.start_minutes == 540
      assert meeting.end_minutes == 630
      assert meeting.room == "Room 101"
      assert meeting.instructors == ["Dr. Smith"]
    end

    test "multiple courses on same day are all present" do
      courses = [
        build_course("10001", "Intro to CS", [
          build_meeting(["Monday"], "09:00", "10:30", "Room 101")
        ]),
        build_course("10002", "Data Structures", [
          build_meeting(["Monday"], "11:00", "12:30", "Room 102")
        ])
      ]

      schedule = build_schedule_owner(courses)

      monday_meetings = Map.get(schedule.meetings_by_day, "Monday")
      assert length(monday_meetings) == 2
      assert Enum.map(monday_meetings, & &1.crn) |> Enum.sort() == ["10001", "10002"]
    end
  end

  describe "data integrity" do
    test "original schedule courses are not mutated" do
      original_meetings = [
        build_meeting(["Monday"], "09:00", "10:30", "Room 101")
      ]

      course = build_course("10001", "Intro to CS", original_meetings)
      schedule = build_schedule_owner([course])

      change =
        build_update_change("10001", "Intro to CS", [
          build_meeting(["Tuesday"], "14:00", "15:30", "Room 999")
        ])

      group = build_change_group([change])
      apply_changes_to_schedule(schedule, group["changes"])

      original_course = hd(schedule.courses)
      assert length(original_course["meet_info"]) == 1
      assert hd(original_course["meet_info"])["room"] == "Room 101"
    end

    test "empty course list with add change works" do
      schedule = build_schedule_owner([])

      change =
        build_add_change("20001", "Solo Course", [
          build_meeting(["Wednesday"], "10:00", "11:30", "Room 404")
        ])

      group = build_change_group([change])
      result = apply_changes_to_schedule(schedule, group["changes"])

      assert length(result.courses) == 1
      assert hd(result.courses)["crn"] == "20001"
      assert length(Map.get(result.meetings_by_day, "Wednesday")) == 1
    end

    test "change for non-existent crn does not affect existing courses" do
      course =
        build_course("10001", "Intro to CS", [
          build_meeting(["Monday"], "09:00", "10:30", "Room 101")
        ])

      schedule = build_schedule_owner([course])

      change =
        build_update_change("99999", "Ghost Course", [
          build_meeting(["Monday"], "14:00", "15:30", "Room 999")
        ])

      group = build_change_group([change])
      result = apply_changes_to_schedule(schedule, group["changes"])

      assert length(result.courses) == 1
      assert hd(result.courses)["crn"] == "10001"
    end

    test "deleted course sentinel removes course from effective schedule" do
      course =
        build_course("10001", "Intro to CS", [
          build_meeting(["Monday"], "09:00", "10:30", "Room 101")
        ])

      schedule = build_schedule_owner([course])

      change = %{
        "crn" => "10001",
        "operation" => "update",
        "course_name" => "__DELETED__",
        "target_professor" => "",
        "meet_info" => []
      }

      result = ScheduleChangeApply.apply_changes(schedule, [change])
      assert result.courses == []
      assert Map.get(result.meetings_by_day, "Monday") == []
    end

    test "schedule_owner preserves program_name and semester_name after rebuild" do
      course =
        build_course("10001", "Intro to CS", [
          build_meeting(["Monday"], "09:00", "10:30", "Room 101")
        ])

      schedule =
        build_schedule_owner([course], :academic_program_semester, "CS:Fall2024")
        |> Map.put(:program_name, "Computer Science")
        |> Map.put(:semester_name, "Fall 2024")

      change =
        build_update_change("10001", "Intro to CS", [
          build_meeting(["Monday"], "10:00", "11:30", "Room 101")
        ])

      group = build_change_group([change])
      result = apply_changes_to_schedule(schedule, group["changes"])

      assert result.program_name == "Computer Science"
      assert result.semester_name == "Fall 2024"
    end
  end

  def build_course(crn, name, meet_info \\ []) do
    %{
      "crn" => crn,
      "name" => name,
      "subject_code" => "CS",
      "course_number" => "101",
      "section_number" => "01",
      "credit_hours" => 3,
      "instructors" => [%{"name" => "Dr. Smith", "primary_instructor" => true}],
      "meet_info" => meet_info
    }
  end

  def build_meeting(days, start_time, end_time, room, building \\ nil)

  def build_meeting(days, start_time, end_time, room, building) do
    room_name =
      ScheduleUtils.room_name(
        meeting: %{
          "room" => room,
          "building" => building,
          "building_code" => nil
        }
      )

    %{
      "days" => days,
      "start_time" => start_time,
      "end_time" => end_time,
      "room" => room,
      "building" => building,
      "__room_name" => room_name,
      "start_minutes" => parse_time(start_time),
      "end_minutes" => parse_time(end_time)
    }
  end

  defp parse_time(time) when is_binary(time) do
    [hour, minute | _] = String.split(time, ":")
    {h, ""} = Integer.parse(hour)
    {m, ""} = Integer.parse(minute)
    h * 60 + m
  end

  def build_change_group(changes \\ []) do
    %{
      "id" => "test_group_1",
      "name" => "Test Scenario",
      "changes" => changes
    }
  end

  def build_add_change(crn, course_name, meet_info \\ nil) do
    %{
      "crn" => crn,
      "operation" => "add",
      "course_name" => course_name,
      "target_professor" => nil,
      "meet_info" =>
        meet_info || [build_meeting(["Monday", "Wednesday"], "09:00", "10:30", "Room 101")]
    }
  end

  def build_update_change(crn, course_name, meet_info \\ nil, professor \\ nil) do
    %{
      "crn" => crn,
      "operation" => "update",
      "course_name" => course_name,
      "target_professor" => professor,
      "meet_info" => meet_info
    }
  end

  def build_schedule_owner(courses, type \\ :academic_program_semester, name \\ "CS:Fall2024") do
    ScheduleUtils.build_week_schedule(type: type, name: name, courses: courses)
  end

  def apply_changes_to_schedule(schedule_owner, changes) when is_list(changes) do
    courses = Map.get(schedule_owner, :courses, [])
    changes_by_crn = Enum.group_by(changes, & &1["crn"])

    updated_courses =
      Enum.flat_map(courses, fn course ->
        case Map.get(changes_by_crn, course["crn"]) do
          nil ->
            [course]

          [%{"operation" => "update"} = change] ->
            [apply_change_to_course(course, change)]

          [%{"operation" => "add"}] ->
            [course]
        end
      end)

    new_courses =
      changes
      |> Enum.filter(&(&1["operation"] == "add"))
      |> Enum.map(&change_to_course/1)

    applied = updated_courses ++ new_courses

    ScheduleUtils.build_week_schedule(
      type: schedule_owner.type,
      name: schedule_owner.name,
      courses: applied
    )
    |> Map.merge(%{
      program_name: schedule_owner[:program_name],
      semester_name: schedule_owner[:semester_name]
    })
  end

  defp apply_change_to_course(course, change) do
    course
    |> Map.put("crn", change["crn"])
    |> Map.put("name", change["course_name"] || course["name"])
    |> Map.put(
      "instructors",
      case change["target_professor"] do
        nil -> course["instructors"]
        prof -> [%{"name" => prof, "primary_instructor" => true}]
      end
    )
    |> Map.put("meet_info", change["meet_info"] || course["meet_info"])
  end

  defp change_to_course(change) do
    %{
      "crn" => change["crn"],
      "name" => change["course_name"] || "",
      "subject_code" => "",
      "course_number" => "",
      "section_number" => "",
      "credit_hours" => 0,
      "instructors" =>
        case change["target_professor"] do
          nil -> []
          prof -> [%{"name" => prof, "primary_instructor" => true}]
        end,
      "meet_info" => change["meet_info"]
    }
  end
end
