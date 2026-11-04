defmodule SnowSeToolsWeb.Scheduling.CardConflictBadgeTest do
  # Reviewing a program's conflicts: each semester card leads with the options
  # that have problems, and every card says at a glance whether it has any.
  use SnowSeToolsWeb.ConnCase, async: true

  alias SnowSeTools.Scheduling.{ScheduleConflictDetector, ScheduleOwnerSchedule, ScheduleUtils}
  alias SnowSeToolsWeb.Scheduling.{CardConflicts, WeekSchedule}

  @program_key "academic_program_semester:p:s"

  # Three sections of CS 1400, one of CS 2420. Section 3 of CS 1400 shares a
  # room and hour with a history class, so only the option using it clashes.
  @courses [
    %{crn: "1", code: {"CS", "1400"}, room: "101", start: "09:00", prof: "a@snow.edu"},
    %{crn: "2", code: {"CS", "1400"}, room: "102", start: "10:00", prof: "a@snow.edu"},
    %{crn: "3", code: {"CS", "1400"}, room: "103", start: "11:00", prof: "a@snow.edu"},
    %{crn: "9", code: {"CS", "2420"}, room: "109", start: "13:00", prof: "b@snow.edu"},
    %{crn: "50", code: {"HIST", "1700"}, room: "103", start: "11:00", prof: "h@snow.edu"}
  ]

  @required [
    %{"subject_code" => "CS", "course_number" => "1400"},
    %{"subject_code" => "CS", "course_number" => "2420"}
  ]

  describe "a program semester's options" do
    test "the option with a conflict comes first, and says what clashes" do
      view = WeekSchedule.view(program_state(), term_conflicts(), nil)

      assert view.count == 3
      assert view.position == 0
      assert view.conflicted_options == 1
      assert crns(view.base) == ["3", "9"]
      assert view.status == :conflicts

      assert [%{heading: "Room: Main 103", courses: courses}] =
               Enum.map(view.conflicts, &CardConflicts.summary/1)

      assert courses =~ "CS 1400"
      assert courses =~ "HIST 1700"
    end

    test "paging on reaches the options without conflicts, in their old order" do
      state = %{program_state() | selected_variant_index: 1}
      view = WeekSchedule.view(state, term_conflicts(), nil)

      assert crns(view.base) == ["1", "9"]
      assert view.conflicts == []
      assert view.status == :clear

      assert crns(
               WeekSchedule.view(%{state | selected_variant_index: 2}, term_conflicts(), nil).base
             ) ==
               ["2", "9"]
    end

    test "a semester that can't be scheduled at all is a conflict" do
      state =
        program_state(
          required: @required ++ [%{"subject_code" => "CS", "course_number" => "9999"}]
        )

      view = WeekSchedule.view(state, term_conflicts(), nil)

      assert view.count == 0
      assert view.gap == {:not_offered, ["CS 9999"]}
      assert view.status == :conflicts
    end

    test "says nothing until the term has been checked" do
      view = WeekSchedule.view(program_state(), %CardConflicts{}, nil)

      assert view.status == :unknown
      assert crns(view.base) == ["1", "9"]
    end
  end

  test "a professor or room card goes by the conflicts that name it" do
    conflicts = term_conflicts()

    assert WeekSchedule.view(owner_state("room:Main 103"), conflicts, nil).status == :conflicts
    assert WeekSchedule.view(owner_state("room:Main 101"), conflicts, nil).status == :clear
  end

  describe "the badge" do
    test "a green check with a 'No conflicts' tooltip" do
      html = render_card(owner_state("room:Main 101"))

      assert html =~ ~s(data-conflict-status="clear")
      assert html =~ "hero-check-circle-solid"
      assert html =~ "No conflicts"
    end

    test "a hazard sign whose tooltip summarises the clash" do
      html = render_card(program_state())

      assert html =~ ~s(data-conflict-status="conflicts")
      assert html =~ "hero-exclamation-triangle-solid"
      assert html =~ "1 conflict in this option"
      assert html =~ "Room: Main 103"
      assert html =~ "1 of 3 options have conflicts; they come first."
      assert html =~ "Option 1 of 3"
      assert html =~ "1 with conflicts"
    end

    test "explains a semester that can't be scheduled" do
      state = program_state(required: [%{"subject_code" => "CS", "course_number" => "9999"}])

      assert render_card(state) =~ "Can&#39;t be scheduled: CS 9999 isn&#39;t offered this term."
    end
  end

  test "a semester whose classes clash is shown with the clash, not blank" do
    # CS 1400 section 3 and HIST 1700 are the only sections, at the same hour.
    state =
      program_state(
        courses: [Enum.at(@courses, 2), Enum.at(@courses, 4)],
        required: [
          %{"subject_code" => "CS", "course_number" => "1400"},
          %{"subject_code" => "HIST", "course_number" => "1700"}
        ]
      )

    view = WeekSchedule.view(state, term_conflicts(), nil)

    assert view.count == 1
    assert crns(view.base) == ["3", "50"]
    assert view.overlap_crns == MapSet.new(["3", "50"])
    assert view.status == :conflicts

    assert "Classes at the same time" in Enum.map(
             view.conflicts,
             &CardConflicts.summary(&1).heading
           )
  end

  test "the gap names the courses with no section this term" do
    courses = Enum.map(@courses, &course/1)

    assert ScheduleUtils.academic_program_semester_gap(courses: courses, required_courses: []) ==
             nil

    assert ScheduleUtils.academic_program_semester_gap(
             courses: courses,
             required_courses: @required
           ) ==
             nil

    assert ScheduleUtils.academic_program_semester_gap(
             courses: courses,
             required_courses: [%{"subject_code" => "CS", "course_number" => "9999"} | @required]
           ) == {:not_offered, ["CS 9999"]}
  end

  defp render_card(state) do
    render_component(&WeekSchedule.render/1,
      state: state,
      position: 0,
      total_count: 1,
      card_conflicts: term_conflicts(),
      editor?: false
    )
  end

  defp term_conflicts do
    courses = Enum.map(@courses, &course/1)

    %{all_conflicts: conflicts} =
      ScheduleConflictDetector.detect_term_conflicts(
        owner_course_lists:
          ScheduleUtils.owner_course_lists(courses: courses, academic_programs: []),
        active_changes: []
      )

    CardConflicts.new(conflicts, checked?: true)
  end

  defp program_state(opts \\ []) do
    required = Keyword.get(opts, :required, @required)
    courses = opts |> Keyword.get(:courses, @courses) |> Enum.map(&course/1)

    variants =
      ScheduleUtils.academic_program_semester_schedule_variants(
        courses: courses,
        required_courses: required
      )

    course_list =
      ScheduleOwnerSchedule.new(
        owner_key: @program_key,
        type: :academic_program_semester,
        name: "Computer Science Freshman first semester",
        courses: if(variants == [], do: [], else: hd(variants).courses),
        opts: [
          program_name: "Computer Science",
          semester_name: "Freshman first semester",
          schedule_variants: variants,
          gap:
            if(variants == [],
              do:
                ScheduleUtils.academic_program_semester_gap(
                  courses: courses,
                  required_courses: required
                )
            )
        ]
      )

    loaded(@program_key, course_list)
  end

  defp owner_state(owner_key) do
    "room:" <> room = owner_key
    courses = @courses |> Enum.map(&course/1) |> Enum.filter(&(room_of(&1) == room))

    loaded(
      owner_key,
      ScheduleOwnerSchedule.new(owner_key: owner_key, type: :room, name: room, courses: courses)
    )
  end

  defp room_of(course) do
    [meeting] = course["meet_info"]
    "#{meeting["building"]} #{meeting["room"]}"
  end

  defp loaded(owner_key, course_list) do
    week_schedule =
      ScheduleUtils.build_week_schedule(
        type: course_list.type,
        name: course_list.name,
        courses: course_list.courses,
        owner_key: owner_key
      )
      |> Map.merge(%{
        program_name: course_list.program_name,
        semester_name: course_list.semester_name,
        schedule_variants: course_list.schedule_variants
      })

    %WeekSchedule{
      owner_key: owner_key,
      selected_term_code: "202590",
      course_list: course_list,
      week_schedule: week_schedule,
      selected_variant_index: 0,
      loading?: false
    }
  end

  defp crns(schedule), do: schedule.courses |> Enum.map(& &1["crn"]) |> Enum.sort()

  defp course(%{crn: crn, code: {subject, number}, room: room, start: start, prof: prof}) do
    %{
      "crn" => crn,
      "term_code" => "202590",
      "subject_code" => subject,
      "course_number" => number,
      "section_number" => "0#{crn}",
      "name" => "#{subject} #{number} class",
      "credit_hours" => 3,
      "instructors" => [%{"name" => prof, "email" => prof, "primary_instructor" => true}],
      "meet_info" => [
        %{
          "building" => "Main",
          "building_code" => "MAI",
          "room" => room,
          "days" => ["Monday", "Wednesday"],
          "start_time" => start,
          "end_time" => String.replace(start, ":00", ":50")
        }
      ]
    }
  end
end
