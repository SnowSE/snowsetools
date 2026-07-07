defmodule SnowSeToolsWeb.Scheduling.CourseChangeIntentTest do
  use ExUnit.Case, async: true

  alias SnowSeToolsWeb.Scheduling.CourseChangeIntent

  test "moving onto a professor reassigns professor and preserves room" do
    {:ok, attrs} =
      CourseChangeIntent.move_course_attrs(
        base_payload()
        |> Map.merge(%{
          "owner_type" => "professor",
          "owner_name" => "Dr. Jones",
          "target_day" => "Tuesday",
          "target_time" => "10:30"
        })
      )

    assert attrs["target_professor"] == "Dr. Jones"
    assert [meeting] = attrs["meet_info"]
    assert meeting["days"] == ["Tuesday", "Thursday"]
    assert meeting["start_time"] == "10:30"
    assert meeting["end_time"] == "11:45"
    assert meeting["building"] == "Main"
    assert meeting["room"] == "101"
  end

  test "moving onto a room reassigns room and preserves professor" do
    {:ok, attrs} =
      CourseChangeIntent.move_course_attrs(
        base_payload()
        |> Map.merge(%{
          "owner_type" => "room",
          "owner_name" => "Science 204",
          "target_day" => "Wednesday",
          "target_time" => "09:00"
        })
      )

    assert attrs["target_professor"] == "Dr. Smith"
    assert [meeting] = attrs["meet_info"]
    assert meeting["days"] == ["Monday", "Wednesday", "Friday"]
    assert meeting["building"] == "Science"
    assert meeting["room"] == "204"
  end

  test "moving inside a program schedule only changes time and days" do
    {:ok, attrs} =
      CourseChangeIntent.move_course_attrs(
        base_payload()
        |> Map.merge(%{
          "owner_type" => "academic_program_semester",
          "owner_name" => "program:semester",
          "target_day" => "Friday",
          "target_time" => "14:00"
        })
      )

    assert attrs["target_professor"] == "Dr. Smith"
    assert [meeting] = attrs["meet_info"]
    assert meeting["days"] == ["Monday", "Wednesday", "Friday"]
    assert meeting["start_time"] == "14:00"
    assert meeting["end_time"] == "14:50"
    assert meeting["building"] == "Main"
    assert meeting["room"] == "101"
  end

  test "editing course can explicitly change professor and room" do
    {:ok, attrs} =
      CourseChangeIntent.edit_course_attrs(
        base_payload()
        |> Map.merge(%{
          "owner_type" => "academic_program_semester",
          "owner_name" => "program:semester",
          "days" => ["Tuesday", "Thursday"],
          "start_time" => "13:00",
          "end_time" => "14:15",
          "target_professor" => "Dr. Jones",
          "target_room" => "Science 204"
        })
      )

    assert attrs["target_professor"] == "Dr. Jones"
    assert [meeting] = attrs["meet_info"]
    assert meeting["days"] == ["Tuesday", "Thursday"]
    assert meeting["start_time"] == "13:00"
    assert meeting["end_time"] == "14:15"
    assert meeting["building"] == "Science"
    assert meeting["room"] == "204"
  end

  test "editing course explicit room overrides current room schedule owner" do
    {:ok, attrs} =
      CourseChangeIntent.edit_course_attrs(
        base_payload()
        |> Map.merge(%{
          "owner_type" => "room",
          "owner_name" => "Main 101",
          "days" => ["Monday"],
          "start_time" => "09:00",
          "end_time" => "09:50",
          "target_room" => "Science 204"
        })
      )

    assert [meeting] = attrs["meet_info"]
    assert meeting["building"] == "Science"
    assert meeting["room"] == "204"
  end

  test "preserving room keeps multi-word building names intact" do
    meeting = %{
      "days" => ["Tuesday", "Thursday"],
      "start_time" => "08:00:00",
      "end_time" => "09:15:00",
      "building" => "Business Building (BUSB)",
      "building_code" => "BUSB",
      "room" => "137"
    }

    {:ok, attrs} =
      CourseChangeIntent.move_course_attrs(
        base_payload()
        |> Map.merge(%{
          "owner_type" => "professor",
          "owner_name" => "Professor Example",
          "target_day" => "Thursday",
          "target_time" => "10:30",
          "meeting" => meeting,
          "meet_info" => [meeting],
          "instructors" => ["Professor Example"]
        })
      )

    assert [updated_meeting] = attrs["meet_info"]
    assert updated_meeting["building"] == "Business Building (BUSB)"
    assert updated_meeting["room"] == "137"
  end

  test "delete attrs use the existing deleted course sentinel" do
    {:ok, attrs} = CourseChangeIntent.delete_course_attrs(base_payload())

    assert attrs["course_name"] == "__DELETED__"
    assert attrs["meet_info"] == []
    assert attrs["operation"] == "update"
  end

  defp base_payload do
    meeting = %{
      "days" => ["Monday", "Wednesday", "Friday"],
      "start_time" => "08:00",
      "end_time" => "08:50",
      "building" => "Main",
      "building_code" => nil,
      "room" => "101"
    }

    %{
      "crn" => "10001",
      "term" => "202501",
      "subject_code" => "CE",
      "course_number" => "2010",
      "course_name" => "Statics",
      "credit_hours" => 3,
      "instructors" => ["Dr. Smith"],
      "meeting" => meeting,
      "meet_info" => [meeting]
    }
  end
end
