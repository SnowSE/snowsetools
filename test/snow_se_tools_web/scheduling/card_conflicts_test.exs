defmodule SnowSeToolsWeb.Scheduling.CardConflictsTest do
  # Where a card's conflicts come from: the term's check (minus what has been
  # acknowledged) and the active change group, and that every view of a
  # program semester -- its own card or an overlay -- shows the same option.
  use SnowSeToolsWeb.ConnCase, async: true

  alias Phoenix.LiveView.Socket
  alias SnowSeTools.Scheduling.{ScheduleConflictDetector, ScheduleOwnerSchedule, ScheduleUtils}

  alias SnowSeToolsWeb.Scheduling.{
    CardConflicts,
    OverlayGroup,
    ScheduleChangeGroups,
    ScheduleTermConflicts,
    WeekSchedule
  }

  import SnowSeToolsWeb.Scheduling.WeekScheduleGrid

  @term "202710"

  describe "the term's conflicts" do
    test "nothing is claimed before the check comes back" do
      state =
        ScheduleTermConflicts.card_conflicts(%ScheduleTermConflicts{selected_term_code: @term})

      refute state.checked?
    end

    test "once checked, each conflict is filed by its classes and the schedules it names" do
      socket = term_checked(room_clash())
      cards = ScheduleTermConflicts.card_conflicts(socket.assigns.schedule_term_conflicts_state)

      assert cards.checked?
      assert [_] = CardConflicts.for_crns(cards, ["1"])
      assert [_] = CardConflicts.for_owner(cards, "room:Main 101")
      assert CardConflicts.for_crns(cards, ["3"]) == []
    end

    test "an acknowledged conflict stops counting against a card" do
      socket = term_checked(room_clash())
      [conflict] = room_clash()

      {:halt, socket} =
        ScheduleTermConflicts.hooked_info(
          {:acknowledged_conflicts,
           {:acknowledged, %{term_code: @term, fingerprint: conflict.fingerprint}}},
          socket
        )

      cards = ScheduleTermConflicts.card_conflicts(socket.assigns.schedule_term_conflicts_state)
      assert cards.checked?
      assert CardConflicts.for_crns(cards, ["1"]) == []
    end

    test "a failed check claims nothing" do
      {:halt, socket} =
        ScheduleTermConflicts.hooked_info(
          {:term_baseline_conflicts_ready, %{term_code: @term, result: {:error, :boom}}},
          socket(%ScheduleTermConflicts{selected_term_code: @term})
        )

      refute ScheduleTermConflicts.card_conflicts(socket.assigns.schedule_term_conflicts_state).checked?
    end
  end

  describe "a program's status, for the Academic Programs button" do
    @semester "academic_program_semester:prog-1:sem-1"

    test "unknown until the term is checked, or for a program the check didn't see" do
      unchecked = %ScheduleTermConflicts{program_options: %{@semester => [option(["9"])]}}
      checked = %{unchecked | checked?: true}

      assert ScheduleTermConflicts.program_status(unchecked, %CardConflicts{}, "prog-1") ==
               :unknown

      assert ScheduleTermConflicts.program_status(checked, %CardConflicts{}, "prog-2") == :unknown
    end

    test "conflicts when an option clashes, or its sections are in a conflict" do
      clashing = checked_with([option(["9"]), option(["8"], true)])
      clean = checked_with([option(["9"]), option(["1"])])
      cards = CardConflicts.new(room_clash(), checked?: true)

      assert ScheduleTermConflicts.program_status(clashing, %CardConflicts{}, "prog-1") ==
               :conflicts

      assert ScheduleTermConflicts.program_status(clean, cards, "prog-1") == :conflicts
    end

    test "clear when no option has either" do
      clean = checked_with([option(["9"]), option(["1"])])

      assert ScheduleTermConflicts.program_status(clean, %CardConflicts{}, "prog-1") == :clear
    end

    test "a semester with no options this term (not offered) is not a conflict" do
      assert ScheduleTermConflicts.program_status(checked_with([]), %CardConflicts{}, "prog-1") ==
               :clear
    end

    test "the active change group's conflicts count" do
      [conflict] = room_clash()
      group = %{"changes" => [%{"id" => "c1", "conflicts" => [conflict]}]}
      cards = ScheduleChangeGroups.active_card_conflicts(%{active_change_group: group})

      assert ScheduleTermConflicts.program_status(checked_with([option(["1"])]), cards, "prog-1") ==
               :conflicts
    end

    test "the term check records each program semester's options" do
      socket = term_checked(room_clash(), %{@semester => [option(["1"])]})
      state = socket.assigns.schedule_term_conflicts_state

      assert state.program_options == %{@semester => [option(["1"])]}

      assert ScheduleTermConflicts.program_status(state, state.card_conflicts, "prog-1") ==
               :conflicts
    end

    defp option(crns, clashes? \\ false), do: %{crns: crns, clashes?: clashes?}

    defp checked_with(options),
      do: %ScheduleTermConflicts{checked?: true, program_options: %{@semester => options}}
  end

  test "the active change group's conflicts count too, and a clash in both counts once" do
    [conflict] = room_clash()
    group = %{"changes" => [%{"id" => "c1", "conflicts" => [conflict]}]}

    active = ScheduleChangeGroups.active_card_conflicts(%{active_change_group: group})

    assert ScheduleChangeGroups.active_card_conflicts(%{active_change_group: nil}) ==
             %CardConflicts{}

    merged = CardConflicts.merge(CardConflicts.new([conflict], checked?: true), active)

    assert merged.checked?
    assert [_one] = CardConflicts.for_crns(merged, ["1", "2"])
  end

  test "an overlay draws the same option of a program semester as its own card" do
    state = program_state()
    cards = CardConflicts.new(room_clash(), checked?: true)

    # Unsorted, option 1 would be the clean section 3; conflicts first, it is
    # the clashing section 1.
    assert crns(WeekSchedule.view(state, cards, nil).base.courses) == ["1", "9"]

    html =
      render_component(&OverlayGroup.render/1,
        group_key: "overlay:1",
        member_keys: [state.owner_key],
        week_schedules: %{state.owner_key => state},
        card_conflicts: cards,
        position: 0,
        total_count: 1,
        editor?: false
      )

    assert html =~ "&quot;crn&quot;:&quot;1&quot;"
    refute html =~ "&quot;crn&quot;:&quot;3&quot;"
  end

  test "the Online box starts open" do
    schedule =
      ScheduleUtils.build_week_schedule(
        type: :academic_program_semester,
        name: "Semester",
        courses: [
          Map.put(course("7", "08:00"), "meet_info", [
            %{"days" => [], "building_code" => "ONLINE"}
          ])
        ]
      )

    html =
      render_component(&schedule_grid/1,
        schedule_owner: schedule,
        owner_key: "academic_program_semester:p:s",
        selected_term_code: @term,
        single_owner_grid: true,
        editor?: false
      )

    assert html =~ ~s(data-open="true")
    assert html =~ ~s(aria-expanded="true")
    assert html =~ "1 class"
  end

  # Section 1 of CS 1400 shares Main 101 at 9:00 with a history class.
  defp room_clash do
    courses = [course("1", "09:00", "101"), course("50", "09:00", "101", "HIST")]

    ScheduleConflictDetector.detect_term_conflicts(
      owner_course_lists:
        ScheduleUtils.owner_course_lists(courses: courses, academic_programs: []),
      active_changes: []
    ).all_conflicts
  end

  defp term_checked(conflicts, program_options \\ %{}) do
    by_owner =
      conflicts
      |> Enum.flat_map(fn conflict -> Enum.map(conflict.owner_keys, &{&1, conflict}) end)
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))

    {:halt, socket} =
      ScheduleTermConflicts.hooked_info(
        {:term_baseline_conflicts_ready,
         %{
           term_code: @term,
           result: {:ok, %{conflicts_by_owner_key: by_owner, program_options: program_options}}
         }},
        socket(%ScheduleTermConflicts{selected_term_code: @term})
      )

    socket
  end

  defp socket(state),
    do: %Socket{assigns: %{__changed__: %{}, schedule_term_conflicts_state: state}}

  defp program_state do
    courses = [
      course("1", "09:00", "101"),
      course("3", "11:00", "103"),
      course("9", "13:00", "109", "CS", "2420")
    ]

    variants =
      ScheduleUtils.academic_program_semester_schedule_variants(
        courses: courses,
        required_courses: [
          %{"subject_code" => "CS", "course_number" => "1400"},
          %{"subject_code" => "CS", "course_number" => "2420"}
        ]
      )

    # The builder's own order puts the clean section 3 first here.
    variants =
      Enum.sort_by(variants, &(&1.courses |> Enum.map(fn c -> c["crn"] end) |> Enum.member?("1")))

    owner_key = "academic_program_semester:p:s"

    course_list =
      ScheduleOwnerSchedule.new(
        owner_key: owner_key,
        type: :academic_program_semester,
        name: "CS Freshman first semester",
        courses: hd(variants).courses,
        opts: [
          program_name: "CS",
          semester_name: "Freshman first semester",
          schedule_variants: variants
        ]
      )

    %WeekSchedule{
      owner_key: owner_key,
      selected_term_code: @term,
      course_list: course_list,
      week_schedule:
        ScheduleUtils.build_week_schedule(
          type: :academic_program_semester,
          name: course_list.name,
          courses: course_list.courses,
          owner_key: owner_key
        )
        |> Map.merge(%{
          program_name: "CS",
          semester_name: "Freshman first semester",
          schedule_variants: variants
        }),
      selected_variant_index: 0,
      loading?: false
    }
  end

  defp crns(courses), do: courses |> Enum.map(& &1["crn"]) |> Enum.sort()

  defp course(crn, start, room \\ nil, subject \\ "CS", number \\ "1400") do
    room = room || "1#{crn}"

    %{
      "crn" => crn,
      "term_code" => @term,
      "subject_code" => subject,
      "course_number" => number,
      "section_number" => "00#{crn}",
      "name" => "#{subject} #{number}",
      "credit_hours" => 3,
      "instructors" => [%{"name" => "Prof #{crn}", "email" => "p#{crn}@snow.edu"}],
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
