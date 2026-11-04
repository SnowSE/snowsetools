defmodule SnowSeTools.Curriculum.ParsingTest do
  use ExUnit.Case, async: true

  alias SnowSeTools.Curriculum.{AbetMatrix, CourseCode, MasterSyllabus, TermLabel, XlsxReader}

  @fixtures Path.expand("../../fixtures/curriculum", __DIR__)

  describe "MasterSyllabus" do
    test "finds the syllabus a course page links to" do
      html = File.read!(Path.join(@fixtures, "course_se3140.html"))
      assert MasterSyllabus.parse_course_page(html) == {:ok, "5757"}
      assert {:error, _reason} = MasterSyllabus.parse_course_page("<html><h1></h1></html>")
    end

    test "reads the fields and outcomes of a master syllabus page" do
      html = File.read!(Path.join(@fixtures, "master_syllabus_se3140.html"))
      assert {:ok, syllabus} = MasterSyllabus.parse_syllabus_page(html)

      assert syllabus["title"] == "SE 3140 Ethics and Craftsmanship"
      assert syllabus["prerequisites"] == "CS 2450 and CS 2860 w/ a minimum grade of C-"
      assert syllabus["corequisites"] == "SE 3630 & SE 3830"
      assert syllabus["semester_approved"] == "Spring 2026"
      assert syllabus["five_year_review"] == "Fall 2030"
      assert syllabus["description"] =~ "ethical and social issues in computing"
      assert length(syllabus["outcomes"]) == 4

      assert syllabus["outcomes"] |> Enum.map(&MasterSyllabus.abet_slos/1) == [[], [], [2], [4]]
    end

    test "a page without the expected layout is an error, not a crash" do
      assert {:error, _reason} =
               MasterSyllabus.parse_syllabus_page("<html><body><p>Maintenance</p></body></html>")
    end

    test "reads ABET tags however they are written" do
      assert MasterSyllabus.abet_slos("… factors. (ABET SLO 2)") == [2]
      assert MasterSyllabus.abet_slos("… (ABET SLOs 1, 2 and 7)") == [1, 2, 7]
      assert MasterSyllabus.abet_slos("(ABET Student Outcome 5)") == [5]
      assert MasterSyllabus.abet_slos("No tag here, just 2026 numbers") == []
    end

    test "drops the lead-in every outcome repeats and compares outcomes loosely" do
      text =
        "Upon successful completion of this course students will be able to demonstrate professional practices."

      assert MasterSyllabus.display_outcome(text) == "Demonstrate professional practices."

      assert MasterSyllabus.normalize_outcome("Write  TESTS, first!") ==
               MasterSyllabus.normalize_outcome("write tests first")
    end
  end

  describe "CourseCode" do
    test "reads codes from prerequisite text, borrowing subjects for bare numbers" do
      assert CourseCode.extract_all("CS 2450 and CS 2860 w/ a minimum grade of C-") ==
               [{"CS", "2450"}, {"CS", "2860"}]

      assert CourseCode.extract_all("MATH 1050 or 1060 (Fall 2026)") ==
               [{"MATH", "1050"}, {"MATH", "1060"}]

      assert CourseCode.extract_all("Math 1210 and (either Math 2040 or Math 3040) with a C") ==
               [{"MATH", "1210"}, {"MATH", "2040"}, {"MATH", "3040"}]

      assert CourseCode.extract_all(nil) == []
    end

    test "reads the code at the start of a column header" do
      assert CourseCode.parse_leading("CS  1410  Object-Oriented Programming") ==
               {:ok, {"CS", "1410"}}

      assert CourseCode.parse_leading("Criteria") == :error
    end
  end

  describe "TermLabel" do
    test "reads terms from folder names and syllabus term names" do
      assert TermLabel.parse("2026-fall-dallan") == {:ok, {2026, 3}}
      assert TermLabel.parse("adam2023_fall") == {:ok, {2023, 3}}
      assert TermLabel.parse("2022Spring") == {:ok, {2022, 1}}
      assert TermLabel.parse("Fall 2026") == {:ok, {2026, 3}}
      assert TermLabel.parse("2026") == {:ok, {2026, nil}}
      assert TermLabel.parse("plans") == :error
    end

    test "keeps every item from the most recent terms, across instructors" do
      folders =
        ~w(2024-fall 2025-spring 2025-fall-jonathan 2026-spring-alex 2026-spring-zac notes)

      assert TermLabel.latest(items: folders, count: 3, label: & &1) ==
               ~w(2026-spring-alex 2026-spring-zac 2025-fall-jonathan 2025-spring)
    end
  end

  describe "ABET matrix workbook" do
    setup do
      {:ok, sheets} =
        @fixtures |> Path.join("abet_matrix_sample.xlsx") |> File.read!() |> XlsxReader.read()

      {:ok, sheets: sheets}
    end

    test "reads every sheet as rows of strings", %{sheets: sheets} do
      assert Enum.map(sheets, & &1.name) == [
               "Main table",
               "proposal fall 2024",
               "Fall2025_Catalog_Matrix",
               "ABET"
             ]
    end

    test "defaults to the newest outcome sheet and the sheet with program criteria", %{
      sheets: sheets
    } do
      assert AbetMatrix.default_slo_sheet(sheets) == "Fall2025_Catalog_Matrix"
      assert AbetMatrix.default_criteria_sheet(sheets) == "Main table"
    end

    test "reads outcomes and course coverage, keeping tentative marks", %{sheets: sheets} do
      assert {:ok, matrix} =
               AbetMatrix.interpret(
                 sheets: sheets,
                 slo_sheet: "Fall2025_Catalog_Matrix",
                 criteria_sheet: "Main table"
               )

      assert Enum.map(matrix.outcomes, & &1.code) ==
               ["SLO 1", "SLO 2", "SLO 3", "PC: Computing fundamentals", "PC: Security"]

      covered = fn code ->
        for c <- matrix.coverage,
            c.code == code,
            do: {c.subject_code, c.course_number, c.tentative}
      end

      assert covered.("SLO 1") == [
               {"CS", "1410", false},
               {"SE", "4620", false},
               {"MATH", "3310", false}
             ]

      assert covered.("SLO 2") == [{"CS", "2450", false}, {"SE", "3140", false}]
      assert covered.("SLO 3") == []
      assert covered.("PC: Security") == [{"SE", "4620", true}]
    end

    test "a file that is not a workbook is an error" do
      assert {:error, _message} = XlsxReader.read("not a zip file")
    end
  end
end
