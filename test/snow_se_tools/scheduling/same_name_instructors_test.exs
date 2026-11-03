defmodule SnowSeTools.Scheduling.SameNameInstructorsTest do
  # Two different people named Michael Olson teach here. Keyed by name, their
  # classes merged into one schedule; keyed by email they stay apart.
  use ExUnit.Case, async: true

  alias SnowSeTools.Scheduling.{
    Instructor,
    ScheduleChange,
    ScheduleConflictDetector,
    ScheduleUtils
  }

  @olson_a %{"name" => "Michael Olson", "email" => "Michael.Olson@snow.edu"}
  @olson_b %{"name" => "Michael Olson", "email" => "michael.olson2@snow.edu"}
  @no_email %{"name" => "Zachary Taylor", "email" => nil}

  describe "Instructor" do
    test "keys a person by lowercased email, and by name only without one" do
      assert Instructor.owner_key(@olson_a) == "professor:michael.olson@snow.edu"
      assert Instructor.owner_key(@olson_b) == "professor:michael.olson2@snow.edu"
      assert Instructor.owner_key(@no_email) == "professor:Zachary Taylor"
    end

    test "labels add the email only where a name is shared" do
      people = Instructor.labels([@olson_a, @olson_b, @no_email, @olson_a])

      assert map_size(people) == 3
      assert people["michael.olson@snow.edu"].label == "Michael Olson (michael.olson@snow.edu)"
      assert people["michael.olson2@snow.edu"].label == "Michael Olson (michael.olson2@snow.edu)"
      assert people["Zachary Taylor"].label == "Zachary Taylor"
    end

    test "resolves a key, an email, a label or an unshared name -- never a shared name" do
      people = Instructor.labels([@olson_a, @olson_b, @no_email])

      assert %{email: "michael.olson2@snow.edu", name: "Michael Olson"} =
               Instructor.resolve("professor:michael.olson2@snow.edu", people)

      assert %{email: "michael.olson@snow.edu"} =
               Instructor.resolve("MICHAEL.OLSON@snow.edu", people)

      assert %{email: "michael.olson2@snow.edu"} =
               Instructor.resolve("Michael Olson (michael.olson2@snow.edu)", people)

      assert %{name: "Zachary Taylor", email: nil} = Instructor.resolve("zachary taylor", people)
      assert Instructor.resolve("Michael Olson", people) == nil
      assert Instructor.resolve("Nobody", people) == nil
    end
  end

  test "each Michael Olson gets his own schedule" do
    lists = professor_lists([course("1", @olson_a, "09:00"), course("2", @olson_b, "13:00")])

    assert %{
             "professor:michael.olson@snow.edu" => ["1"],
             "professor:michael.olson2@snow.edu" => ["2"]
           } = lists
  end

  test "a week grid draws only the classes of the person it is keyed to" do
    courses = [course("1", @olson_a, "09:00"), course("2", @olson_b, "13:00")]

    schedule =
      ScheduleUtils.build_week_schedule(
        type: :professor,
        name: "Michael Olson (michael.olson2@snow.edu)",
        courses: courses,
        owner_key: "professor:michael.olson2@snow.edu"
      )

    assert schedule.meetings_by_day |> Map.values() |> List.flatten() |> Enum.map(& &1.crn) ==
             ["2"]
  end

  describe "conflicts" do
    test "two people who share a name are not double-booked by teaching at once" do
      assert professor_conflicts([course("1", @olson_a, "09:00"), course("2", @olson_b, "09:00")]) ==
               []
    end

    test "one person teaching two classes at once still conflicts, labelled by name" do
      assert [conflict] =
               professor_conflicts([
                 course("1", @olson_b, "09:00"),
                 course("2", @olson_b, "09:00", "R2b")
               ])

      assert conflict.resource_label == "Michael Olson"
      assert "professor:michael.olson2@snow.edu" in conflict.owner_keys
      refute "professor:michael.olson@snow.edu" in conflict.owner_keys
    end
  end

  test "a class handed to someone carries their email, so it lands on their schedule" do
    change = %{
      "crn" => "1",
      "operation" => "update",
      "target_professor" => "Michael Olson",
      "target_professor_email" => "michael.olson2@snow.edu"
    }

    [moved] =
      ScheduleChange.apply_changes(courses: [course("1", @olson_a, "09:00")], changes: [change])

    assert [instructor] = moved["instructors"]
    assert Instructor.owner_key(instructor) == "professor:michael.olson2@snow.edu"
  end

  defp professor_lists(courses) do
    ScheduleUtils.owner_course_lists(courses: courses, academic_programs: [])
    |> Enum.filter(&(&1.type == :professor))
    |> Map.new(&{&1.owner_key, Enum.map(&1.courses, fn course -> course["crn"] end)})
  end

  defp professor_conflicts(courses) do
    ScheduleConflictDetector.detect_term_conflicts(
      owner_course_lists:
        ScheduleUtils.owner_course_lists(courses: courses, academic_programs: []),
      active_changes: []
    ).all_conflicts
    |> Enum.filter(&(&1.type == :professor))
  end

  defp course(crn, instructor, start_time, room \\ nil) do
    %{
      "crn" => crn,
      "term_code" => "202790",
      "subject_code" => "SE",
      "course_number" => "10#{crn}0",
      "section_number" => "01",
      "name" => Enum.at(~w(Databases Networks Compilers), rem(String.to_integer(crn), 3)),
      "credit_hours" => 3,
      "instructors" => [Map.put(instructor, "primary_instructor", true)],
      "meet_info" => [
        %{
          "building" => "Main",
          "building_code" => "MAI",
          # Separate rooms unless asked, so only professor conflicts can arise.
          "room" => room || "R#{crn}",
          "days" => ["Monday"],
          "start_time" => start_time,
          "end_time" => start_time |> String.replace(":00", ":50")
        }
      ]
    }
  end
end
