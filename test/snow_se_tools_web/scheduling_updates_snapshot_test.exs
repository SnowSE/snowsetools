defmodule SnowSeToolsWeb.SchedulingUpdatesSnapshotTest do
  @moduledoc """
  Not a test: the source of the screenshots on the scheduling Updates tab.

  Seeds a small, made-up term -- invented instructors with example.edu emails,
  because the screenshots are committed to a public repository -- walks the
  real LiveView into each state a feature is shown in, and writes the HTML to
  tmp/updates. `scheduling_update_screenshots.sh` turns those into the images
  under priv/static/images/updates/scheduling. Excluded from the suite.
  """
  use SnowSeToolsWeb.ConnCase, async: false

  @moduletag :snapshot

  alias SnowSeTools.AcademicPrograms.{ProgramAttrs, ProgramDomainManager}
  alias SnowSeTools.Scheduling.{ScheduleChangeDomainManager, ScheduleOwnerDomainManager}
  alias SnowSeTools.Snow.{SnowCourseCacheDb, SnowCourseCacheDomainManager}

  @out "tmp/updates"
  @term "202710"

  @lee {"Jordan Lee", "jordan.lee@example.edu"}
  @shah {"Priya Shah", "priya.shah@example.edu"}
  @rivera {"Alex Rivera", "alex.rivera@example.edu"}
  @blake {"Morgan Blake", "morgan.blake@example.edu"}
  @ortiz {"Sam Ortiz", "sam.ortiz@example.edu"}
  @park {"Riley Park", "riley.park@example.edu"}
  @nguyen {"Casey Nguyen", "casey.nguyen@example.edu"}
  # Two different people with the same name.
  @smith_a {"Taylor Smith", "taylor.smith@example.edu"}
  @smith_b {"Taylor Smith", "tsmith2@example.edu"}

  setup do
    File.rm_rf!(@out)
    File.mkdir_p!(@out)
    seed_courses()

    start_supervised!(ProgramDomainManager)
    start_supervised!(SnowCourseCacheDomainManager)
    start_supervised!(ScheduleOwnerDomainManager)
    start_supervised!(ScheduleChangeDomainManager)

    software =
      create_program("Software Engineering", [
        ~w(CS-1400 CS-1405 CS-1430 COMM-2110),
        ~w(CS-1410 CS-1415 MATH-1210 CS-1810 ENGL-2010),
        ~w(CS-2860 MATH-2270)
      ])

    electrical =
      create_program("Electrical Engineering", [
        ~w(ENGR-1400 ENGR-1405 MATH-1220 PHYS-2210 PHYS-2215),
        ~w(ENGR-2240 MATH-2250)
      ])

    minor = create_program("Software Engineering Minor", [~w(CS-1430 CS-1810)])

    %{software: software, electrical: electrical, minor: minor}
  end

  test "dump the scheduling update states", %{
    conn: conn,
    software: software,
    electrical: electrical,
    minor: minor
  } do
    conn = log_in_user(conn, "updates-snapshot@example.com", ["scheduling_admin"])

    # The Academic Programs tab, once the term's check has answered.
    view = programs_tab(conn)
    select(view, software)
    await_button(view, "conflicts")
    dump("programs-review", view)

    select(view, minor)
    await_button(view, "clear")
    dump("programs-no-conflicts", view)

    # Reviewing a program on an empty canvas opens its semesters.
    view = programs_tab(conn)
    select(view, software)
    review(view)
    await_cards(view, 3)
    dump("software-review", view)

    # Its first semester's second option: the one without a conflict.
    [first_semester | _] = semester_keys(software)
    view |> element(~s([id="schedule-variant-next-#{first_semester}"])) |> render_click()
    dump("software-review-option-2", view)

    view = programs_tab(conn)
    select(view, electrical)
    review(view)
    await_cards(view, 2)
    dump("electrical-review", view)

    # With unsaved work on the canvas, reviewing asks first.
    view = programs_tab(conn)
    [minor_semester] = semester_keys(minor)
    render_click(view, "schedule-details-order:toggle", %{"key" => minor_semester})
    select(view, electrical)
    review(view)
    assert has_element?(view, "#schedule-program-choice")
    dump("program-choice", view)

    # Two people named Taylor Smith in schedule search.
    {:ok, view, _html} = live(conn, ~p"/scheduling?mode=viewer&term=#{@term}")
    :ok = ScheduleOwnerDomainManager.await_idle()
    render_hook(view, "schedule-layouts:session_read", %{"session" => nil})
    view |> form("#scheduling-search-form") |> render_change(%{"query" => "Taylor Smith"})
    dump("same-name-search", view)

    # The Updates tab itself, to look over before it goes out.
    {:ok, view, _html} = live(conn, ~p"/scheduling?mode=updates")
    dump("updates-page", view)
  end

  defp programs_tab(conn) do
    {:ok, view, _html} = live(conn, ~p"/scheduling?mode=programs&term=#{@term}")
    _ = :sys.get_state(ProgramDomainManager)
    :ok = ScheduleOwnerDomainManager.await_idle()
    render_hook(view, "schedule-layouts:session_read", %{"session" => nil})
    view
  end

  defp select(view, program),
    do: view |> element("#academic-program-#{program["id"]}") |> render_click()

  defp review(view),
    do: view |> element("#review-program-schedule-conflicts") |> render_click()

  defp await_button(view, status) do
    assert eventually(fn ->
             has_element?(
               view,
               ~s(#review-program-schedule-conflicts[data-conflict-status="#{status}"])
             )
           end)
  end

  # Every card loaded and carrying its badge, i.e. the term has been checked.
  defp await_cards(view, count) do
    assert eventually(fn ->
             :ok = ScheduleOwnerDomainManager.await_idle()

             html = render(view)

             length(Regex.scan(~r/data-conflict-status="(clear|conflicts)"/, html)) >= count and
               not (html =~ "Loading schedule")
           end)
  end

  defp eventually(check, tries \\ 150) do
    cond do
      check.() -> true
      tries == 0 -> false
      true -> Process.sleep(20) && eventually(check, tries - 1)
    end
  end

  defp dump(name, view), do: File.write!(Path.join(@out, "#{name}.html"), render(view))

  defp create_program(name, semesters) do
    {:ok, attrs} =
      ProgramAttrs.parse(%{
        name: name,
        semesters:
          Enum.map(semesters, fn codes ->
            %{
              courses:
                Enum.map(codes, fn code ->
                  [subject, number] = String.split(code, "-")
                  %{subject_code: subject, course_number: number}
                end)
            }
          end)
      })

    ProgramDomainManager.create_program(pid: self(), program: attrs)
    assert_receive {:academic_programs, {:action_result, {:ok, _message, program}}}
    _ = :sys.get_state(ScheduleOwnerDomainManager)
    program
  end

  defp semester_keys(program) do
    Enum.map(program["semesters"], fn semester ->
      "academic_program_semester:#{program["id"]}:#{semester["id"]}"
    end)
  end

  @mwf ~w(Monday Wednesday Friday)
  @mtwf ~w(Monday Tuesday Wednesday Friday)
  @tth ~w(Tuesday Thursday)

  defp seed_courses do
    courses = [
      # Software Engineering, freshman fall: each lab goes with its own
      # lecture, and Riley Park is booked twice at 1:30.
      section(
        "2001",
        "CS",
        "1400",
        "001",
        "Programming I",
        @smith_a,
        @mwf,
        "09:30",
        "10:20",
        "HLIB",
        "024A"
      ),
      section(
        "2002",
        "CS",
        "1400",
        "002",
        "Programming I",
        @park,
        @mwf,
        "13:30",
        "14:20",
        "GRSC",
        "142"
      ),
      online("2003", "CS", "1400", "N01", "Programming I", @smith_a),
      section(
        "2004",
        "CS",
        "1405",
        "001",
        "Programming I Lab",
        @smith_a,
        ["Tuesday"],
        "09:30",
        "11:20",
        "GRSC",
        "143"
      ),
      section(
        "2005",
        "CS",
        "1405",
        "002",
        "Programming I Lab",
        @park,
        ["Tuesday"],
        "13:30",
        "15:20",
        "GRSC",
        "142"
      ),
      online("2006", "CS", "1405", "N01", "Programming I Lab", @smith_a),
      section(
        "2007",
        "CS",
        "1430",
        "001",
        "Problem Solving",
        @blake,
        @tth,
        "12:00",
        "13:15",
        "HLIB",
        "024B"
      ),
      section(
        "2008",
        "COMM",
        "2110",
        "001",
        "Interpersonal Communication",
        @ortiz,
        @mwf,
        "11:30",
        "12:20",
        "HUMAN",
        "158"
      ),
      section(
        "2009",
        "CS",
        "2420",
        "001",
        "Data Structures",
        @park,
        @mwf,
        "13:30",
        "14:20",
        "HLIB",
        "024B"
      ),
      # Software Engineering, freshman spring: fits, with one online-only class.
      section(
        "2010",
        "CS",
        "1410",
        "001",
        "Programming II",
        @smith_b,
        @mwf,
        "08:30",
        "09:20",
        "HLIB",
        "024A"
      ),
      section(
        "2011",
        "CS",
        "1415",
        "001",
        "Programming II Lab",
        @smith_b,
        ["Tuesday"],
        "08:30",
        "10:20",
        "GRSC",
        "143"
      ),
      section(
        "2012",
        "MATH",
        "1210",
        "001",
        "Calculus I",
        @shah,
        ~w(Monday Tuesday Wednesday Thursday Friday),
        "10:30",
        "11:20",
        "GRSC",
        "124"
      ),
      section(
        "2013",
        "CS",
        "1810",
        "001",
        "Intro to Cybersecurity",
        @blake,
        @tth,
        "13:30",
        "14:45",
        "HLIB",
        "024A"
      ),
      online("2014", "ENGL", "2010", "N01", "Intermediate Writing", @nguyen),
      # Software Engineering, sophomore spring: two single sections at once.
      section(
        "2015",
        "CS",
        "2860",
        "001",
        "Systems Programming",
        @ortiz,
        @mwf,
        "09:30",
        "10:20",
        "HLIB",
        "024B"
      ),
      section(
        "2016",
        "MATH",
        "2270",
        "001",
        "Linear Algebra",
        @shah,
        @mwf,
        "09:30",
        "10:20",
        "GRSC",
        "122"
      ),
      # Electrical Engineering, freshman spring: the labs collide on Thursday,
      # and only the online ENGR 1405 avoids it.
      section(
        "2017",
        "ENGR",
        "1400",
        "001",
        "Intro to Electrical Engineering",
        @lee,
        @mwf,
        "14:30",
        "15:20",
        "GRSC",
        "142"
      ),
      online("2018", "ENGR", "1400", "N01", "Intro to Electrical Engineering", @lee),
      section(
        "2019",
        "ENGR",
        "1405",
        "001",
        "Intro to Electrical Engineering Lab",
        @lee,
        ["Thursday"],
        "13:30",
        "15:20",
        "GRSC",
        "142"
      ),
      online("2020", "ENGR", "1405", "N01", "Intro to Electrical Engineering Lab", @lee),
      section(
        "2021",
        "MATH",
        "1220",
        "001",
        "Calculus II",
        @shah,
        @mtwf,
        "10:30",
        "11:20",
        "GRSC",
        "122"
      ),
      section(
        "2022",
        "MATH",
        "1220",
        "1F1",
        "Calculus II",
        @nguyen,
        @mtwf,
        "13:30",
        "14:20",
        "NOYES",
        "140"
      ),
      section(
        "2023",
        "PHYS",
        "2210",
        "001",
        "Physics for Scientists I",
        @rivera,
        @mtwf,
        "13:30",
        "14:20",
        "GRSC",
        "341"
      ),
      section(
        "2024",
        "PHYS",
        "2215",
        "001",
        "Physics for Scientists I Lab",
        @rivera,
        ["Thursday"],
        "13:30",
        "16:20",
        "GRSC",
        "351"
      ),
      # Electrical Engineering, sophomore fall: ENGR 2240 is a fall course.
      section(
        "2025",
        "MATH",
        "2250",
        "001",
        "Differential Equations",
        @shah,
        @mtwf,
        "14:30",
        "15:20",
        "GRSC",
        "223"
      )
    ]

    :ok =
      SnowCourseCacheDb.save_courses(term_code: @term, term_name: "Spring 2027", courses: courses)
  end

  defp section(
         crn,
         subject,
         number,
         section,
         name,
         {instructor, email},
         days,
         start,
         finish,
         building,
         room
       ) do
    base(crn, subject, number, section, name, instructor, email, "Ephraim Campus", [
      %{
        "building" => building,
        "building_code" => building,
        "room" => room,
        "days" => days,
        "start_time" => start <> ":00",
        "end_time" => finish <> ":00"
      }
    ])
  end

  defp online(crn, subject, number, section, name, {instructor, email}) do
    base(crn, subject, number, section, name, instructor, email, "Online", [
      %{
        "building" => "Online Class (ONLINE)",
        "building_code" => "ONLINE",
        "room" => "ONLINE",
        "days" => [],
        "start_time" => nil,
        "end_time" => nil
      }
    ])
  end

  defp base(crn, subject, number, section, name, instructor, email, campus, meet_info) do
    %{
      "crn" => crn,
      "term_code" => @term,
      "subject_code" => subject,
      "course_number" => number,
      "section_number" => section,
      "name" => name,
      "credit_hours" => 3,
      "campus" => campus,
      "instructors" => [%{"name" => instructor, "email" => email, "primary_instructor" => true}],
      "meet_info" => meet_info
    }
  end
end
