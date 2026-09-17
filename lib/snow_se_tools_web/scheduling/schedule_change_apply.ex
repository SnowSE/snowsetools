defmodule SnowSeToolsWeb.Scheduling.ScheduleChangeApply do
  @moduledoc """
  A schedule owner's week with a change group applied, for drawing.

  The rules for what a change does to a course live in
  `SnowSeTools.Scheduling.ScheduleChange`; this only decides which of the
  resulting courses belong on this owner's card.
  """

  alias SnowSeTools.Scheduling.{ScheduleChange, ScheduleUtils}

  def apply_changes(%{type: type, name: name} = schedule_owner, changes) when is_list(changes) do
    courses = Map.get(schedule_owner, :courses, [])

    applied =
      courses_on_this_card(
        courses: courses,
        changes: changes,
        owner_type: type,
        owner_name: name
      )

    ScheduleUtils.build_week_schedule(
      type: type,
      name: name,
      courses: applied
    )
    |> Map.merge(%{
      program_name: schedule_owner[:program_name],
      semester_name: schedule_owner[:semester_name]
    })
  end

  def effective_schedule(schedule_owner, nil), do: schedule_owner

  def effective_schedule(schedule_owner, active_change_group) do
    changes = Map.get(active_change_group, "changes", [])
    apply_changes(schedule_owner, changes)
  end

  defp courses_on_this_card(
         courses: courses,
         changes: changes,
         owner_type: owner_type,
         owner_name: owner_name
       )
       when is_list(courses) and is_list(changes) do
    changed = ScheduleChange.apply_changes(courses: courses, changes: changes)

    moved_in =
      moved_in_courses(courses: courses, changes: changes, owner_type: owner_type)

    (changed ++ moved_in)
    |> Enum.filter(
      &course_matches_owner?(course: &1, owner_type: owner_type, owner_name: owner_name)
    )
  end

  # A program semester lists the courses it requires; nothing moves into it.
  defp moved_in_courses(
         courses: _courses,
         changes: _changes,
         owner_type: :academic_program_semester
       ),
       do: []

  defp moved_in_courses(courses: courses, changes: changes, owner_type: _owner_type),
    do: ScheduleChange.moved_courses(courses: courses, changes: changes)

  defp course_matches_owner?(
         course: _course,
         owner_type: :academic_program_semester,
         owner_name: _owner_name
       ),
       do: true

  defp course_matches_owner?(course: course, owner_type: :room, owner_name: owner_name) do
    Enum.any?(course["meet_info"] || [], fn meeting ->
      ScheduleUtils.room_name(meeting: meeting) == owner_name
    end)
  end

  defp course_matches_owner?(course: course, owner_type: :professor, owner_name: owner_name) do
    Enum.any?(course["instructors"] || [], fn instructor ->
      instructor["name"] == owner_name
    end)
  end

  defp course_matches_owner?(course: _course, owner_type: _owner_type, owner_name: _owner_name),
    do: true
end
