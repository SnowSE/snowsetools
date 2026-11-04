defmodule SnowSeTools.Curriculum.SectionSyllabi do
  @moduledoc """
  The per-section syllabi this site already syncs from Simple Syllabus, as
  extra evidence of what a course teaches: schedules, assignment lists and
  required tools often name skills the master syllabus does not.

  Sections are titled "SE 3820 001 (CRN: 4389)". This reads the sections of
  the course's three most recent terms, skipping copies whose text is the same.
  """

  alias SnowSeTools.Curriculum.TermLabel
  alias SnowSeTools.Data.DbHelpers

  @terms_to_read 3

  def read_course(subject_code: subject_code, course_number: course_number, budget: budget) do
    sql = """
    SELECT code, title, term_name, detail_data
    FROM syllabi
    WHERE title LIKE $(prefix) AND detail_data IS NOT NULL
    """

    case DbHelpers.query(sql, %{"prefix" => "#{subject_code} #{course_number} %"}) do
      {:ok, rows} ->
        sections =
          rows
          |> then(
            &TermLabel.latest(
              items: &1,
              count: @terms_to_read,
              label: fn row -> row["term_name"] end
            )
          )
          |> Enum.map(&{&1, syllabus_text(&1["detail_data"])})
          |> Enum.reject(fn {_row, text} -> text == "" end)
          |> Enum.uniq_by(fn {_row, text} -> text end)

        {:ok,
         %{
           text: join_within(sections, budget),
           sections:
             Enum.map(sections, fn {row, _text} -> "#{row["title"]} — #{row["term_name"]}" end)
         }}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp join_within(sections, budget) do
    sections
    |> Enum.reduce_while({[], budget}, fn {row, text}, {chunks, remaining} ->
      if remaining <= 0 do
        {:halt, {chunks, remaining}}
      else
        chunk = "### #{row["title"]} (#{row["term_name"]})\n#{String.slice(text, 0, remaining)}"
        {:cont, {[chunk | chunks], remaining - String.length(chunk)}}
      end
    end)
    |> elem(0)
    |> Enum.reverse()
    |> Enum.join("\n\n")
  end

  defp syllabus_text(%{"components" => components}) when is_list(components) do
    components
    |> Enum.sort_by(& &1["sort_order"])
    |> Enum.map_join("\n\n", fn component ->
      name = component["name"] || ""
      text = (component["html"] || "") |> HtmlSanitizeEx.strip_tags() |> String.trim()
      if name != "", do: "## #{name}\n#{text}", else: text
    end)
    |> String.trim()
  end

  defp syllabus_text(_no_components), do: ""
end
