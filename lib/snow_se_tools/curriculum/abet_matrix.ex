defmodule SnowSeTools.Curriculum.AbetMatrix do
  @moduledoc """
  Interprets the department's ABET matrix workbook: one row per ABET student
  outcome ("1. an ability to identify, formulate…") or program criterion, one
  column per course ("CS  1410  Object-Oriented Programming"), and a mark in
  each cell the course covers.

  Marks are read loosely because the sheets disagree: "1", "x" and "X" mean
  covered, "?" means tentatively covered, and "0" or blank mean not covered.
  """

  alias SnowSeTools.Curriculum.{CourseCode, TermLabel}

  @criteria_marker ~r/^program criteria/i
  @slo_row ~r/^(\d)\.\s*(.+)$/s

  @doc "Sheets that have student outcome rows under a row of course columns."
  def slo_sheet_names(sheets) do
    for sheet <- sheets, slo_rows(sheet) != [], do: sheet.name
  end

  @doc "Sheets that have a \"Program Criteria\" section."
  def criteria_sheet_names(sheets) do
    for sheet <- sheets, criteria_rows(sheet) != [], do: sheet.name
  end

  @doc """
  The sheet to read student outcomes from when nobody picks one: the one whose
  name carries the newest year (Fall2025_Catalog_Matrix over a 2024 proposal),
  else the first that has outcome rows.
  """
  def default_slo_sheet(sheets) do
    names = slo_sheet_names(sheets)

    dated =
      for name <- names, {:ok, term} <- [TermLabel.parse(name)] do
        {TermLabel.sort_key(term), name}
      end

    case Enum.max_by(dated, &elem(&1, 0), fn -> nil end) do
      {_term, name} -> name
      nil -> List.first(names)
    end
  end

  def default_criteria_sheet(sheets), do: sheets |> criteria_sheet_names() |> List.first()

  @doc """
  The outcomes and the course coverage the chosen sheets describe:

      %{outcomes: [%{code, kind, number, title, position}],
        coverage: [%{subject_code, course_number, code, tentative}]}
  """
  def interpret(sheets: sheets, slo_sheet: slo_sheet_name, criteria_sheet: criteria_sheet_name) do
    with {:ok, slo_sheet} <- find_sheet(sheets, slo_sheet_name),
         {:ok, criteria_sheet} <- find_optional_sheet(sheets, criteria_sheet_name) do
      slos =
        for {row, title, number} <- slo_rows(slo_sheet) do
          {%{code: "SLO #{number}", kind: "slo", number: number, title: title, position: number},
           row}
        end

      criteria =
        for {{row, title}, index} <- Enum.with_index(criteria_rows(criteria_sheet)) do
          {%{
             code: "PC: #{title}",
             kind: "criterion",
             number: nil,
             title: title,
             position: 100 + index
           }, row}
        end

      if slos == [] do
        {:error, "The sheet \"#{slo_sheet_name}\" has no ABET student outcome rows."}
      else
        {:ok,
         %{
           outcomes: Enum.map(slos ++ criteria, &elem(&1, 0)),
           coverage:
             coverage(slos, course_columns(slo_sheet)) ++
               coverage(criteria, course_columns(criteria_sheet))
         }}
      end
    end
  end

  defp find_sheet(sheets, name) do
    case Enum.find(sheets, &(&1.name == name)) do
      nil -> {:error, "The workbook has no sheet named \"#{name}\"."}
      sheet -> {:ok, sheet}
    end
  end

  defp find_optional_sheet(_sheets, nil), do: {:ok, nil}
  defp find_optional_sheet(_sheets, ""), do: {:ok, nil}
  defp find_optional_sheet(sheets, name), do: find_sheet(sheets, name)

  defp coverage(rows, columns) do
    for {%{code: code}, row} <- rows,
        {index, {subject, number}} <- columns,
        mark = row |> Enum.at(index, "") |> mark(),
        mark != :none do
      %{subject_code: subject, course_number: number, code: code, tentative: mark == :tentative}
    end
  end

  defp mark(cell) do
    case cell |> clean() |> String.downcase() do
      value when value in ["1", "x", "yes", "✓"] -> :covered
      "?" -> :tentative
      _blank_or_zero -> :none
    end
  end

  # The header row is the first row naming several courses; every other row
  # is read against its columns.
  defp header_index(nil), do: nil

  defp header_index(sheet) do
    Enum.find_index(sheet.rows, fn row ->
      Enum.count(row, &match?({:ok, _code}, CourseCode.parse_leading(clean(&1)))) >= 3
    end)
  end

  defp course_columns(nil), do: []

  defp course_columns(sheet) do
    case header_index(sheet) do
      nil ->
        []

      index ->
        sheet.rows
        |> Enum.at(index)
        |> Enum.with_index()
        |> Enum.flat_map(fn {cell, column} ->
          case CourseCode.parse_leading(clean(cell)) do
            {:ok, code} -> [{column, code}]
            :error -> []
          end
        end)
    end
  end

  defp slo_rows(sheet) do
    case header_index(sheet) do
      nil ->
        []

      index ->
        criteria_at = criteria_start(sheet) || length(sheet.rows)

        sheet.rows
        |> Enum.with_index()
        |> Enum.filter(fn {_row, row_index} -> row_index > index and row_index < criteria_at end)
        |> Enum.flat_map(fn {row, _row_index} ->
          case row |> criteria_cell() |> then(&Regex.run(@slo_row, &1)) do
            [_full, number, title] -> [{row, sentence(title), String.to_integer(number)}]
            nil -> []
          end
        end)
    end
  end

  defp criteria_rows(nil), do: []

  defp criteria_rows(sheet) do
    case {header_index(sheet), criteria_start(sheet)} do
      {header, start} when is_integer(header) and is_integer(start) ->
        sheet.rows
        |> Enum.drop(start + 1)
        |> Enum.map(&{&1, criteria_cell(&1)})
        |> Enum.reject(fn {_row, title} -> title == "" end)
        |> Enum.map(fn {row, title} -> {row, sentence(title)} end)

      _missing ->
        []
    end
  end

  defp criteria_start(sheet) do
    Enum.find_index(sheet.rows, &Regex.match?(@criteria_marker, criteria_cell(&1)))
  end

  # The description sits in the "Criteria" column; in every sheet so far that
  # is the third column.
  defp criteria_cell(row), do: row |> Enum.at(2, "") |> clean()

  defp sentence(text) do
    case String.trim(text) do
      <<first::utf8, rest::binary>> -> String.upcase(<<first::utf8>>) <> rest
      "" -> ""
    end
  end

  defp clean(cell), do: cell |> String.replace(~r/\x{00A0}/u, " ") |> String.trim()
end
