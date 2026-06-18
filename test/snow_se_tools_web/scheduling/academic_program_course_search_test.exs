defmodule SnowSeToolsWeb.Scheduling.AcademicProgramCourseSearchTest do
  use ExUnit.Case, async: true

  alias SnowSeToolsWeb.Scheduling.AcademicProgramCourseSearch

  describe "course_input_value/1" do
    test "joins subject code and course number" do
      course = %{"subject_code" => "MATH", "course_number" => "1010"}

      assert AcademicProgramCourseSearch.course_input_value(course) == "MATH 1010"
    end
  end

  describe "parse_course_input/1" do
    test "splits a normal course code" do
      assert AcademicProgramCourseSearch.parse_course_input("math 1010") == {"MATH", "1010"}
    end

    test "splits a compact course code" do
      assert AcademicProgramCourseSearch.parse_course_input("math1010") == {"MATH", "1010"}
    end

    test "keeps a numeric fragment when the subject is missing" do
      assert AcademicProgramCourseSearch.parse_course_input("1010") == {"", "1010"}
    end
  end

  describe "course_suggestions/2" do
    test "matches by code and label while deduplicating courses" do
      courses = [
        %{"subject_code" => "MATH", "course_number" => "1010", "name" => "Calculus I"},
        %{
          "subject_code" => "MATH",
          "course_number" => "1010",
          "name" => "Calculus I (duplicate)"
        },
        %{"subject_code" => "CE", "course_number" => "2010", "name" => "Statics"}
      ]

      suggestions = AcademicProgramCourseSearch.course_suggestions(courses, "calc")

      assert [%{value: "MATH 1010", label: "Calculus I"}] = suggestions
    end
  end
end
