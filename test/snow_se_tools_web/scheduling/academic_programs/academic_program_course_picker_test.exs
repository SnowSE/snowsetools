defmodule SnowSeToolsWeb.Scheduling.AcademicProgramCoursePickerTest do
  use ExUnit.Case, async: true

  alias SnowSeToolsWeb.Scheduling.AcademicPrograms.AcademicProgramEditor
  alias SnowSeToolsWeb.Scheduling.AcademicProgramCoursePicker

  test "deduplicates course suggestions across all semesters" do
    picker_state = %AcademicProgramCoursePicker{
      key: :academic_program_course_picker,
      course_catalog: [
        %{
          value: "CE 2010",
          label: "Statics",
          subject_code: "CE",
          course_number: "2010",
          value_norm: "ce2010",
          label_norm: "statics",
          subject_code_norm: "ce",
          course_number_norm: "2010"
        }
      ],
      course_label_by_value: %{"CE 2010" => "Statics"},
      course_focus_request: nil,
      course_focus_token: 0,
      picker_open: %{},
      picker_active_indexes: %{}
    }

    editor_state = %AcademicProgramEditor{
      editor: %{
        "semesters" => [
          %{"courses" => [%{"subject_code" => "CE", "course_number" => "2010"}]},
          %{"courses" => [%{"subject_code" => "CE", "course_number" => "2010"}]}
        ]
      }
    }

    render_state = AcademicProgramCoursePicker.render_assigns(picker_state, editor_state, 0, 0)

    assert [%{value: "CE 2010", label: "Statics"}] = render_state.suggestions
    assert render_state.matched_course_label == "Statics"
  end
end
