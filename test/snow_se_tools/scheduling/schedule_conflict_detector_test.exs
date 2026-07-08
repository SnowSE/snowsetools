defmodule SnowSeTools.Scheduling.ScheduleConflictDetectorTest do
  use ExUnit.Case, async: true

  alias SnowSeTools.Scheduling.{ScheduleConflictDetector, ScheduleOwnerSchedule}

  # -- Existing tests (preserved) --

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
    course_data = course(crn: "10001")

    result =
      ScheduleConflictDetector.detect_term_conflicts(
        owner_course_lists: [
          schedule_owner(
            owner_key: "room:Main 101",
            type: :room,
            name: "Main 101",
            courses: [course_data]
          ),
          schedule_owner(
            owner_key: "professor:Professor One",
            type: :professor,
            name: "Professor One",
            courses: [course_data]
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

  # -- N-way consolidation tests (from previous refactor) --

  test "three courses sharing a professor produce one consolidated conflict, not three" do
    result =
      ScheduleConflictDetector.detect_term_conflicts(
        owner_course_lists:
          owner_course_lists([
            course(crn: "10001", professor: "Professor A"),
            course(crn: "10002", professor: "Professor A"),
            course(crn: "10003", professor: "Professor A")
          ]),
        active_changes: []
      )

    prof_conflicts = Enum.filter(result.all_conflicts, &(&1.type == :professor))
    room_conflicts = Enum.filter(result.all_conflicts, &(&1.type == :room))

    assert length(prof_conflicts) == 1,
           "expected 1 professor conflict, got #{length(prof_conflicts)}"

    assert length(room_conflicts) == 1, "expected 1 room conflict, got #{length(room_conflicts)}"

    [%{course_crns: crns}] = prof_conflicts
    assert Enum.sort(crns) == ["10001", "10002", "10003"]
  end

  test "three courses in same room produce one consolidated room conflict" do
    result =
      ScheduleConflictDetector.detect_term_conflicts(
        owner_course_lists:
          owner_course_lists([
            course(crn: "10001", professor: "Professor A", room: "Lab 201"),
            course(crn: "10002", professor: "Professor B", room: "Lab 201"),
            course(crn: "10003", professor: "Professor C", room: "Lab 201")
          ]),
        active_changes: []
      )

    room_conflicts = Enum.filter(result.all_conflicts, &(&1.type == :room))
    assert length(room_conflicts) == 1, "expected 1 room conflict, got #{length(room_conflicts)}"

    [%{course_crns: crns}] = room_conflicts
    assert Enum.sort(crns) == ["10001", "10002", "10003"]
  end

  # -- New tests: resource-first partitioning prevents bridge-entry false positives --

  test "does not create bridge conflicts: non-overlapping same-room courses are safe" do
    # Course A and B share Main 101 but have non-overlapping times.
    # Course C is in a different room and overlaps with both A and B temporally.
    # Bug (old approach): C acts as a bridge, grouping {A,B,C} by time,
    # then room_conflicts finds A+B share Main 101 → false conflict.
    # Fix: partition by room FIRST. Room Main 101 has {A,B}, check overlap → none.

    result =
      ScheduleConflictDetector.detect_term_conflicts(
        owner_course_lists: [
          schedule_owner(
            owner_key: "room:Main 101",
            type: :room,
            name: "Main 101",
            courses: [
              course(
                crn: "10001",
                professor: "Prof A",
                room: "Main 101",
                start_time: "09:00:00",
                end_time: "09:50:00"
              ),
              course(
                crn: "10002",
                professor: "Prof B",
                room: "Main 101",
                start_time: "10:40:00",
                end_time: "11:30:00"
              )
            ]
          ),
          schedule_owner(
            owner_key: "room:Other 200",
            type: :room,
            name: "Other 200",
            courses: [
              course(
                crn: "10003",
                professor: "Prof C",
                room: "Other 200",
                start_time: "09:30:00",
                end_time: "11:00:00"
              )
            ]
          ),
          schedule_owner(
            owner_key: "professor:Prof A",
            type: :professor,
            name: "Prof A",
            courses: [
              course(
                crn: "10001",
                professor: "Prof A",
                room: "Main 101",
                start_time: "09:00:00",
                end_time: "09:50:00"
              )
            ]
          ),
          schedule_owner(
            owner_key: "professor:Prof B",
            type: :professor,
            name: "Prof B",
            courses: [
              course(
                crn: "10002",
                professor: "Prof B",
                room: "Main 101",
                start_time: "10:40:00",
                end_time: "11:30:00"
              )
            ]
          ),
          schedule_owner(
            owner_key: "professor:Prof C",
            type: :professor,
            name: "Prof C",
            courses: [
              course(
                crn: "10003",
                professor: "Prof C",
                room: "Other 200",
                start_time: "09:30:00",
                end_time: "11:00:00"
              )
            ]
          )
        ],
        active_changes: []
      )

    assert result.all_conflicts == [],
           "expected no conflicts, got #{inspect(result.all_conflicts, pretty: true)}"
  end

  test "detects room conflict only for overlapping courses, not all same-room courses" do
    # Three courses in Lab 201: A+B overlap, C is at a different time.
    # Only A and B should be in the room conflict, not C.
    result =
      ScheduleConflictDetector.detect_term_conflicts(
        owner_course_lists: [
          schedule_owner(
            owner_key: "room:Lab 201",
            type: :room,
            name: "Lab 201",
            courses: [
              course(
                crn: "10001",
                professor: "Prof A",
                room: "Lab 201",
                start_time: "09:00:00",
                end_time: "09:50:00"
              ),
              course(
                crn: "10002",
                professor: "Prof B",
                room: "Lab 201",
                start_time: "09:30:00",
                end_time: "10:20:00"
              ),
              course(
                crn: "10003",
                professor: "Prof C",
                room: "Lab 201",
                start_time: "14:00:00",
                end_time: "14:50:00"
              )
            ]
          ),
          schedule_owner(
            owner_key: "professor:Prof A",
            type: :professor,
            name: "Prof A",
            courses: [
              course(
                crn: "10001",
                professor: "Prof A",
                room: "Lab 201",
                start_time: "09:00:00",
                end_time: "09:50:00"
              )
            ]
          ),
          schedule_owner(
            owner_key: "professor:Prof B",
            type: :professor,
            name: "Prof B",
            courses: [
              course(
                crn: "10002",
                professor: "Prof B",
                room: "Lab 201",
                start_time: "09:30:00",
                end_time: "10:20:00"
              )
            ]
          ),
          schedule_owner(
            owner_key: "professor:Prof C",
            type: :professor,
            name: "Prof C",
            courses: [
              course(
                crn: "10003",
                professor: "Prof C",
                room: "Lab 201",
                start_time: "14:00:00",
                end_time: "14:50:00"
              )
            ]
          )
        ],
        active_changes: []
      )

    room_conflicts = Enum.filter(result.all_conflicts, &(&1.type == :room))

    assert length(room_conflicts) == 1,
           "expected exactly 1 room conflict (A+B), got #{length(room_conflicts)}"

    [%{course_crns: crns}] = room_conflicts

    assert Enum.sort(crns) == ["10001", "10002"],
           "expected only overlapping courses, got #{inspect(crns)}"
  end

  test "detects multiple independent conflict groups within same room" do
    # Room Lab 201: A+B overlap in the morning, D+E overlap in the afternoon.
    # Should produce TWO separate room conflicts.
    result =
      ScheduleConflictDetector.detect_term_conflicts(
        owner_course_lists: [
          schedule_owner(
            owner_key: "room:Lab 201",
            type: :room,
            name: "Lab 201",
            courses: [
              course(
                crn: "10001",
                professor: "Prof A",
                room: "Lab 201",
                start_time: "09:00:00",
                end_time: "09:50:00"
              ),
              course(
                crn: "10002",
                professor: "Prof B",
                room: "Lab 201",
                start_time: "09:30:00",
                end_time: "10:20:00"
              ),
              course(
                crn: "10003",
                professor: "Prof C",
                room: "Lab 201",
                start_time: "14:00:00",
                end_time: "14:50:00"
              ),
              course(
                crn: "10004",
                professor: "Prof D",
                room: "Lab 201",
                start_time: "14:30:00",
                end_time: "15:20:00"
              )
            ]
          ),
          schedule_owner(
            owner_key: "professor:Prof A",
            type: :professor,
            name: "Prof A",
            courses: [
              course(
                crn: "10001",
                professor: "Prof A",
                room: "Lab 201",
                start_time: "09:00:00",
                end_time: "09:50:00"
              )
            ]
          ),
          schedule_owner(
            owner_key: "professor:Prof B",
            type: :professor,
            name: "Prof B",
            courses: [
              course(
                crn: "10002",
                professor: "Prof B",
                room: "Lab 201",
                start_time: "09:30:00",
                end_time: "10:20:00"
              )
            ]
          ),
          schedule_owner(
            owner_key: "professor:Prof C",
            type: :professor,
            name: "Prof C",
            courses: [
              course(
                crn: "10003",
                professor: "Prof C",
                room: "Lab 201",
                start_time: "14:00:00",
                end_time: "14:50:00"
              )
            ]
          ),
          schedule_owner(
            owner_key: "professor:Prof D",
            type: :professor,
            name: "Prof D",
            courses: [
              course(
                crn: "10004",
                professor: "Prof D",
                room: "Lab 201",
                start_time: "14:30:00",
                end_time: "15:20:00"
              )
            ]
          )
        ],
        active_changes: []
      )

    room_conflicts = Enum.filter(result.all_conflicts, &(&1.type == :room))

    assert length(room_conflicts) == 2,
           "expected 2 room conflicts (A+B and D+E), got #{length(room_conflicts)}"
  end

  test "professor bridge entry does not create false room conflicts" do
    # Prof A teaches Course A (Room X, 9-10) and Course B (Room Y, 9-10).
    # Room X also has Course C (Prof D, 9:30-10:30) which overlaps with A.
    # Room Y also has Course D (Prof E, 9:30-10:30) which overlaps with B.
    # Should produce: 2 professor conflicts (A is double-booked), not room false positives.

    result =
      ScheduleConflictDetector.detect_term_conflicts(
        owner_course_lists: [
          schedule_owner(
            owner_key: "room:Room X",
            type: :room,
            name: "Room X",
            courses: [
              course(
                crn: "10001",
                professor: "Prof A",
                room: "Room X",
                start_time: "09:00:00",
                end_time: "09:50:00"
              ),
              course(
                crn: "10003",
                professor: "Prof D",
                room: "Room X",
                start_time: "09:30:00",
                end_time: "10:20:00"
              )
            ]
          ),
          schedule_owner(
            owner_key: "room:Room Y",
            type: :room,
            name: "Room Y",
            courses: [
              course(
                crn: "10002",
                professor: "Prof A",
                room: "Room Y",
                start_time: "09:00:00",
                end_time: "09:50:00"
              ),
              course(
                crn: "10004",
                professor: "Prof E",
                room: "Room Y",
                start_time: "09:30:00",
                end_time: "10:20:00"
              )
            ]
          ),
          schedule_owner(
            owner_key: "professor:Prof A",
            type: :professor,
            name: "Prof A",
            courses: [
              course(
                crn: "10001",
                professor: "Prof A",
                room: "Room X",
                start_time: "09:00:00",
                end_time: "09:50:00"
              ),
              course(
                crn: "10002",
                professor: "Prof A",
                room: "Room Y",
                start_time: "09:00:00",
                end_time: "09:50:00"
              )
            ]
          ),
          schedule_owner(
            owner_key: "professor:Prof D",
            type: :professor,
            name: "Prof D",
            courses: [
              course(
                crn: "10003",
                professor: "Prof D",
                room: "Room X",
                start_time: "09:30:00",
                end_time: "10:20:00"
              )
            ]
          ),
          schedule_owner(
            owner_key: "professor:Prof E",
            type: :professor,
            name: "Prof E",
            courses: [
              course(
                crn: "10004",
                professor: "Prof E",
                room: "Room Y",
                start_time: "09:30:00",
                end_time: "10:20:00"
              )
            ]
          )
        ],
        active_changes: []
      )

    prof_conflicts = Enum.filter(result.all_conflicts, &(&1.type == :professor))
    room_conflicts = Enum.filter(result.all_conflicts, &(&1.type == :room))

    # Prof A teaches two courses at same time → 1 professor conflict
    assert length(prof_conflicts) == 1,
           "expected 1 professor conflict (Prof A double-booked), got #{length(prof_conflicts)}"

    # Room X: A+C overlap → 1 room conflict. Room Y: B+D overlap → 1 room conflict.
    assert length(room_conflicts) == 2,
           "expected 2 room conflicts (Room X: A+C, Room Y: B+D), got #{length(room_conflicts)}"
  end

  # -- Same-course exemption tests --

  test "does not conflict when a professor teaches two sections of the same course at the same time" do
    result =
      ScheduleConflictDetector.detect_term_conflicts(
        owner_course_lists: [
          schedule_owner(
            owner_key: "professor:Prof A",
            type: :professor,
            name: "Prof A",
            courses: [
              course(
                crn: "10001",
                professor: "Prof A",
                room: "Room X",
                subject_code: "MATH",
                course_number: "101"
              ),
              course(
                crn: "10002",
                professor: "Prof A",
                room: "Room Y",
                subject_code: "MATH",
                course_number: "101"
              )
            ]
          ),
          schedule_owner(
            owner_key: "room:Room X",
            type: :room,
            name: "Room X",
            courses: [
              course(
                crn: "10001",
                professor: "Prof A",
                room: "Room X",
                subject_code: "MATH",
                course_number: "101"
              )
            ]
          ),
          schedule_owner(
            owner_key: "room:Room Y",
            type: :room,
            name: "Room Y",
            courses: [
              course(
                crn: "10002",
                professor: "Prof A",
                room: "Room Y",
                subject_code: "MATH",
                course_number: "101"
              )
            ]
          )
        ],
        active_changes: []
      )

    prof_conflicts = Enum.filter(result.all_conflicts, &(&1.type == :professor))

    assert prof_conflicts == [],
           "expected no professor conflict for same course, got #{inspect(prof_conflicts)}"
  end

  test "does not conflict when two rooms host sections of the same course at the same time" do
    result =
      ScheduleConflictDetector.detect_term_conflicts(
        owner_course_lists: [
          schedule_owner(
            owner_key: "room:Room A",
            type: :room,
            name: "Room A",
            courses: [
              course(
                crn: "20001",
                professor: "Prof X",
                room: "Room A",
                subject_code: "CHEM",
                course_number: "201"
              )
            ]
          ),
          schedule_owner(
            owner_key: "room:Room B",
            type: :room,
            name: "Room B",
            courses: [
              course(
                crn: "20002",
                professor: "Prof Y",
                room: "Room B",
                subject_code: "CHEM",
                course_number: "201"
              )
            ]
          ),
          schedule_owner(
            owner_key: "professor:Prof X",
            type: :professor,
            name: "Prof X",
            courses: [
              course(
                crn: "20001",
                professor: "Prof X",
                room: "Room A",
                subject_code: "CHEM",
                course_number: "201"
              )
            ]
          ),
          schedule_owner(
            owner_key: "professor:Prof Y",
            type: :professor,
            name: "Prof Y",
            courses: [
              course(
                crn: "20002",
                professor: "Prof Y",
                room: "Room B",
                subject_code: "CHEM",
                course_number: "201"
              )
            ]
          )
        ],
        active_changes: []
      )

    room_conflicts = Enum.filter(result.all_conflicts, &(&1.type == :room))

    assert room_conflicts == [],
           "expected no room conflict for same course, got #{inspect(room_conflicts)}"
  end

  test "does not conflict when two professors co-teach the same course at the same time" do
    # Scenario: Prof A and Prof B both assigned to MATH 101 on Monday 9-10 in Room X.
    # Each professor's schedule includes the course with identical instructor lists.
    # This is a legitimate co-teaching arrangement — not a conflict.
    result =
      ScheduleConflictDetector.detect_term_conflicts(
        owner_course_lists: [
          schedule_owner(
            owner_key: "professor:Prof A",
            type: :professor,
            name: "Prof A",
            courses: [
              co_taught_course(crn: "30001", professors: ["Prof A", "Prof B"])
            ]
          ),
          schedule_owner(
            owner_key: "professor:Prof B",
            type: :professor,
            name: "Prof B",
            courses: [
              co_taught_course(crn: "30001", professors: ["Prof A", "Prof B"])
            ]
          ),
          schedule_owner(
            owner_key: "room:Room X",
            type: :room,
            name: "Room X",
            courses: [
              co_taught_course(crn: "30001", professors: ["Prof A", "Prof B"])
            ]
          )
        ],
        active_changes: []
      )

    prof_conflicts = Enum.filter(result.all_conflicts, &(&1.type == :professor))
    room_conflicts = Enum.filter(result.all_conflicts, &(&1.type == :room))

    assert prof_conflicts == [],
           "expected no professor conflict for co-teaching, got #{inspect(prof_conflicts)}"

    assert room_conflicts == [],
           "expected no room conflict for co-teaching, got #{inspect(room_conflicts)}"
  end

  test "co-teaching exemption does not hide real conflicts between different courses" do
    # Prof A co-teaches MATH 101 with Prof B AND also teaches PHYS 201 solo.
    # Both at the same time → PROF A should still be flagged (MATH 101 vs PHYS 201).
    result =
      ScheduleConflictDetector.detect_term_conflicts(
        owner_course_lists: [
          schedule_owner(
            owner_key: "professor:Prof A",
            type: :professor,
            name: "Prof A",
            courses: [
              co_taught_course(crn: "30010", professors: ["Prof A", "Prof B"]),
              course(
                crn: "30020",
                professor: "Prof A",
                room: "Room Z",
                subject_code: "PHYS",
                course_number: "201"
              )
            ]
          ),
          schedule_owner(
            owner_key: "professor:Prof B",
            type: :professor,
            name: "Prof B",
            courses: [
              co_taught_course(crn: "30010", professors: ["Prof A", "Prof B"])
            ]
          ),
          schedule_owner(
            owner_key: "room:Room X",
            type: :room,
            name: "Room X",
            courses: [
              co_taught_course(crn: "30010", professors: ["Prof A", "Prof B"])
            ]
          ),
          schedule_owner(
            owner_key: "room:Room Z",
            type: :room,
            name: "Room Z",
            courses: [
              course(
                crn: "30020",
                professor: "Prof A",
                room: "Room Z",
                subject_code: "PHYS",
                course_number: "201"
              )
            ]
          )
        ],
        active_changes: []
      )

    prof_conflicts = Enum.filter(result.all_conflicts, &(&1.type == :professor))

    assert length(prof_conflicts) == 1,
           "expected 1 professor conflict for Prof A teaching MATH 101 + PHYS 201, got #{inspect(prof_conflicts)}"

    assert Enum.at(prof_conflicts, 0).course_crns == ["30010", "30020"]
  end

  test "ignores TBA Staff as a professor resource in conflict detection" do
    # "TBA Staff" is a placeholder professor used by the registrar for courses
    # where the actual instructor has not yet been assigned. It should never be
    # flagged as conflicting with itself or any other professor.
    result =
      ScheduleConflictDetector.detect_term_conflicts(
        owner_course_lists: [
          schedule_owner(
            owner_key: "professor:TBA Staff",
            type: :professor,
            name: "TBA Staff",
            courses: [
              course(
                crn: "40001",
                professor: "TBA Staff",
                room: "Room A",
                subject_code: "MATH",
                course_number: "101"
              ),
              course(
                crn: "40002",
                professor: "TBA Staff",
                room: "Room B",
                subject_code: "PHYS",
                course_number: "201"
              )
            ]
          ),
          schedule_owner(
            owner_key: "room:Room A",
            type: :room,
            name: "Room A",
            courses: [
              course(
                crn: "40001",
                professor: "TBA Staff",
                room: "Room A",
                subject_code: "MATH",
                course_number: "101"
              )
            ]
          ),
          schedule_owner(
            owner_key: "room:Room B",
            type: :room,
            name: "Room B",
            courses: [
              course(
                crn: "40002",
                professor: "TBA Staff",
                room: "Room B",
                subject_code: "PHYS",
                course_number: "201"
              )
            ]
          )
        ],
        active_changes: []
      )

    prof_conflicts = Enum.filter(result.all_conflicts, &(&1.type == :professor))

    assert prof_conflicts == [],
           "expected no professor conflicts for TBA Staff, got #{inspect(prof_conflicts)}"
  end

  test "TBA Staff on one course does not hide real conflicts for another professor" do
    # Prof A teaches MATH 101 (co-taught with TBA Staff) and PHYS 201 solo.
    # TBA Staff should not interfere — Prof A's real conflict should still appear.
    result =
      ScheduleConflictDetector.detect_term_conflicts(
        owner_course_lists: [
          schedule_owner(
            owner_key: "professor:Prof A",
            type: :professor,
            name: "Prof A",
            courses: [
              co_taught_course(crn: "40010", professors: ["Prof A", "TBA Staff"]),
              course(
                crn: "40020",
                professor: "Prof A",
                room: "Room Z",
                subject_code: "PHYS",
                course_number: "201"
              )
            ]
          ),
          schedule_owner(
            owner_key: "professor:TBA Staff",
            type: :professor,
            name: "TBA Staff",
            courses: [
              co_taught_course(crn: "40010", professors: ["Prof A", "TBA Staff"])
            ]
          ),
          schedule_owner(
            owner_key: "room:Room X",
            type: :room,
            name: "Room X",
            courses: [
              co_taught_course(crn: "40010", professors: ["Prof A", "TBA Staff"])
            ]
          ),
          schedule_owner(
            owner_key: "room:Room Z",
            type: :room,
            name: "Room Z",
            courses: [
              course(
                crn: "40020",
                professor: "Prof A",
                room: "Room Z",
                subject_code: "PHYS",
                course_number: "201"
              )
            ]
          )
        ],
        active_changes: []
      )

    prof_conflicts = Enum.filter(result.all_conflicts, &(&1.type == :professor))

    assert length(prof_conflicts) == 1,
           "expected 1 professor conflict for Prof A (MATH 101 + PHYS 201), got #{inspect(prof_conflicts)}"

    # TBA Staff should NOT appear in the owner keys of this conflict
    refute Enum.any?(prof_conflicts, fn c -> "professor:TBA Staff" in c.owner_keys end)
  end

  # -- Helpers --

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
      "subject_code" => Keyword.get(opts, :subject_code, "C#{crn}"),
      "course_number" => Keyword.get(opts, :course_number, crn),
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

  defp co_taught_course(opts) do
    crn = Keyword.fetch!(opts, :crn)
    professors = Keyword.fetch!(opts, :professors)

    %{
      "crn" => crn,
      "term_code" => "202777",
      "subject_code" => Keyword.get(opts, :subject_code, "MATH"),
      "course_number" => Keyword.get(opts, :course_number, "101"),
      "section_number" => "01",
      "name" => Keyword.get(opts, :name, "Course #{crn}"),
      "credit_hours" => 1,
      "instructors" =>
        Enum.map(professors, fn name ->
          %{"name" => name, "primary_instructor" => true}
        end),
      "meet_info" => [
        meeting(
          room: Keyword.get(opts, :room, "Room X"),
          days: Keyword.get(opts, :days, ["Monday"]),
          start_time: Keyword.get(opts, :start_time, "09:00:00"),
          end_time: Keyword.get(opts, :end_time, "09:50:00")
        )
      ]
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
