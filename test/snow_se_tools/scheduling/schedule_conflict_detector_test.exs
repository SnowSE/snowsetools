defmodule SnowSeTools.Scheduling.ScheduleConflictDetectorTest do
  use ExUnit.Case, async: true

  alias SnowSeTools.Scheduling.{ScheduleConflictDetector, ScheduleOwnerSchedule}

  test "detects room conflicts across term owner schedules" do
    result =
      ScheduleConflictDetector.detect_term_conflicts(
        owner_course_lists:
          owner_course_lists([
            course(crn: "10001", professor: "Professor One"),
            course(crn: "10002", professor: "Professor Two")
          ]),
        active_changes: []
      )

    assert [%{type: :room} = conflict] = result.all_conflicts
    assert "room:Main 101" in conflict.owner_keys
    assert Map.has_key?(result.conflicts_by_owner_key, "room:Main 101")
  end

  test "detects professor conflicts across term owner schedules" do
    result =
      ScheduleConflictDetector.detect_term_conflicts(
        owner_course_lists:
          owner_course_lists([
            course(crn: "10001", professor: "Professor One", room: "Main 101"),
            course(crn: "10002", professor: "Professor One", room: "Main 102")
          ]),
        active_changes: []
      )

    assert [%{type: :professor} = conflict] = result.all_conflicts
    assert "professor:Professor One" in conflict.owner_keys
    assert Map.has_key?(result.conflicts_by_owner_key, "professor:Professor One")
  end

  test "does not conflict when times touch but do not overlap" do
    result =
      ScheduleConflictDetector.detect_term_conflicts(
        owner_course_lists:
          owner_course_lists([
            course(crn: "10001", start_time: "09:00:00", end_time: "09:50:00"),
            course(crn: "10002", start_time: "09:50:00", end_time: "10:40:00")
          ]),
        active_changes: []
      )

    assert result.all_conflicts == []
  end

  test "does not conflict when days do not overlap" do
    result =
      ScheduleConflictDetector.detect_term_conflicts(
        owner_course_lists:
          owner_course_lists([
            course(crn: "10001", days: ["Monday"]),
            course(crn: "10002", days: ["Tuesday"])
          ]),
        active_changes: []
      )

    assert result.all_conflicts == []
  end

  test "does not compare a course with itself through multiple owner schedules" do
    course = course(crn: "10001")

    result =
      ScheduleConflictDetector.detect_term_conflicts(
        owner_course_lists: [
          schedule_owner(
            owner_key: "room:Main 101",
            type: :room,
            name: "Main 101",
            courses: [course]
          ),
          schedule_owner(
            owner_key: "professor:Professor One",
            type: :professor,
            name: "Professor One",
            courses: [course]
          )
        ],
        active_changes: []
      )

    assert result.all_conflicts == []
  end

  test "active change introduces a conflict against an unselected term owner" do
    changed_course =
      course(crn: "10001", room: "Source 100", start_time: "09:00:00", end_time: "09:50:00")

    target_course =
      course(
        crn: "10002",
        professor: "Professor Two",
        room: "Target 200",
        start_time: "10:45:00",
        end_time: "11:30:00"
      )

    result =
      ScheduleConflictDetector.detect_term_conflicts(
        owner_course_lists: owner_course_lists([changed_course, target_course]),
        active_changes: [
          %{
            "id" => "change-1",
            "crn" => "10001",
            "term" => "202777",
            "subject_code" => "TEST",
            "course_number" => "1010",
            "course_name" => "Changed Course",
            "target_professor" => "Professor One",
            "operation" => "update",
            "meet_info" => [
              meeting(room: "Target 200", start_time: "10:30:00", end_time: "11:20:00")
            ]
          }
        ]
      )

    assert [%{type: :room} = conflict] = result.conflicts_by_change_id["change-1"]
    assert "room:Target 200" in conflict.owner_keys
  end

  test "active change can resolve an existing conflict" do
    result =
      ScheduleConflictDetector.detect_term_conflicts(
        owner_course_lists: owner_course_lists([course(crn: "10001"), course(crn: "10002")]),
        active_changes: [
          %{
            "id" => "change-1",
            "crn" => "10001",
            "term" => "202777",
            "subject_code" => "TEST",
            "course_number" => "1010",
            "course_name" => "Changed Course",
            "target_professor" => "Professor One",
            "operation" => "update",
            "meet_info" => [
              meeting(room: "Main 101", start_time: "11:00:00", end_time: "11:50:00")
            ]
          }
        ]
      )

    assert result.all_conflicts == []
    assert result.conflicts_by_change_id == %{}
  end

  defp owner_course_lists(courses) do
    courses
    |> Enum.flat_map(fn course ->
      [
        schedule_owner(
          owner_key: "room:#{room_name(List.first(course["meet_info"]))}",
          type: :room,
          name: room_name(List.first(course["meet_info"])),
          courses: [course]
        ),
        schedule_owner(
          owner_key: "professor:#{first_professor(course)}",
          type: :professor,
          name: first_professor(course),
          courses: [course]
        )
      ]
    end)
  end

  defp schedule_owner(owner_key: owner_key, type: type, name: name, courses: courses) do
    ScheduleOwnerSchedule.new(owner_key: owner_key, type: type, name: name, courses: courses)
  end

  defp course(opts) do
    crn = Keyword.fetch!(opts, :crn)

    %{
      "crn" => crn,
      "term_code" => "202777",
      "subject_code" => "TEST",
      "course_number" => Keyword.get(opts, :course_number, "1010"),
      "section_number" => "01",
      "name" => Keyword.get(opts, :name, "Course #{crn}"),
      "credit_hours" => 1,
      "instructors" => [
        %{
          "name" => Keyword.get(opts, :professor, "Professor One"),
          "primary_instructor" => true
        }
      ],
      "meet_info" => [
        meeting(
          room: Keyword.get(opts, :room, "Main 101"),
          days: Keyword.get(opts, :days, ["Monday"]),
          start_time: Keyword.get(opts, :start_time, "09:00:00"),
          end_time: Keyword.get(opts, :end_time, "09:50:00")
        )
      ]
    }
  end

  defp meeting(opts) do
    room = Keyword.fetch!(opts, :room)

    %{
      "building" => building(room),
      "building_code" => String.slice(building(room), 0, 3),
      "room" => room_number(room),
      "days" => Keyword.get(opts, :days, ["Monday"]),
      "start_time" => Keyword.fetch!(opts, :start_time),
      "end_time" => Keyword.fetch!(opts, :end_time)
    }
  end

  defp room_name(meeting), do: "#{meeting["building"]} #{meeting["room"]}"
  defp first_professor(course), do: course["instructors"] |> List.first() |> Map.fetch!("name")

  defp building(room) do
    room
    |> String.split(" ")
    |> Enum.drop(-1)
    |> Enum.join(" ")
  end

  defp room_number(room) do
    room
    |> String.split(" ")
    |> List.last()
  end
end
