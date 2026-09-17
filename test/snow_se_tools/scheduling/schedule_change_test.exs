defmodule SnowSeTools.Scheduling.ScheduleChangeTest do
  use ExUnit.Case, async: true

  alias SnowSeTools.Scheduling.ScheduleChange

  @meeting %{
    "days" => ["Monday"],
    "start_time" => "09:00",
    "end_time" => "09:50",
    "building" => "Main",
    "room" => "101"
  }

  defp course(attrs \\ %{}) do
    Map.merge(
      %{
        "crn" => "10001",
        "name" => "Networking",
        "subject_code" => "TEST",
        "course_number" => "1130",
        "instructors" => [%{"name" => "Ada", "primary_instructor" => true}],
        "meet_info" => [@meeting]
      },
      attrs
    )
  end

  defp change(attrs \\ %{}) do
    Map.merge(
      %{
        "crn" => "10001",
        "term" => "202501",
        "operation" => "update",
        "course_name" => "Networking",
        "subject_code" => "TEST",
        "course_number" => "1130",
        "meet_info" => [@meeting]
      },
      attrs
    )
  end

  describe "apply_changes/1" do
    test "a course with no change is left exactly as it was" do
      courses = [course()]

      assert ScheduleChange.apply_changes(courses: courses, changes: []) == courses
    end

    test "an update rewrites the course and marks where it came from" do
      [applied] =
        ScheduleChange.apply_changes(
          courses: [course()],
          changes: [change(%{"target_professor" => "Grace", "course_name" => "Networking II"})]
        )

      assert applied["name"] == "Networking II"
      assert applied["instructors"] == [%{"name" => "Grace", "primary_instructor" => true}]
      assert applied["__source"] == :updated
    end

    # The drift that mattered: one copy wiped the instructors when a change
    # carried a blank professor, the other left them alone. A blank professor
    # says nothing about who teaches the course.
    test "a blank professor leaves the instructors alone" do
      for blank <- [nil, "", "   "] do
        [applied] =
          ScheduleChange.apply_changes(
            courses: [course()],
            changes: [change(%{"target_professor" => blank})]
          )

        assert applied["instructors"] == [%{"name" => "Ada", "primary_instructor" => true}],
               "expected #{inspect(blank)} to leave the instructors alone"
      end
    end

    test "a deletion drops the course" do
      assert ScheduleChange.apply_changes(
               courses: [course()],
               changes: [change(%{"course_name" => ScheduleChange.deleted_marker()})]
             ) == []
    end

    test "an add materializes a course that was not there" do
      [applied] =
        ScheduleChange.apply_changes(
          courses: [],
          changes: [change(%{"crn" => "20002", "operation" => "add"})]
        )

      assert applied["crn"] == "20002"
      assert applied["__source"] == :added
      assert applied["term_code"] == "202501"
    end

    test "an add for a course already on hand does not duplicate it" do
      applied =
        ScheduleChange.apply_changes(
          courses: [course()],
          changes: [change(%{"operation" => "add"})]
        )

      assert length(applied) == 1
      assert hd(applied)["__source"] == nil
    end

    # One copy silently kept the last change, the other raised a CaseClauseError.
    test "two changes for one course mean the later one wins" do
      [applied] =
        ScheduleChange.apply_changes(
          courses: [course()],
          changes: [
            change(%{"target_professor" => "Grace"}),
            change(%{"target_professor" => "Katherine"})
          ]
        )

      assert applied["instructors"] == [%{"name" => "Katherine", "primary_instructor" => true}]
    end
  end

  describe "moved_courses/1" do
    test "carries in a course this set does not have yet, marked as new here" do
      [moved] =
        ScheduleChange.moved_courses(
          courses: [course(%{"crn" => "99999"})],
          changes: [change(%{"target_professor" => "Grace"})]
        )

      assert moved["crn"] == "10001"
      assert moved["__source"] == :added
      assert moved["instructors"] == [%{"name" => "Grace", "primary_instructor" => true}]
    end

    test "ignores courses already here, and deletions" do
      assert ScheduleChange.moved_courses(courses: [course()], changes: [change()]) == []

      assert ScheduleChange.moved_courses(
               courses: [],
               changes: [change(%{"course_name" => ScheduleChange.deleted_marker()})]
             ) == []
    end
  end
end
