defmodule SnowSeToolsWeb.Scheduling.AcademicProgramCourseSearch do
  @moduledoc false

  @max_suggestions 8

  def course_input_value(course) when is_map(course) do
    [Map.get(course, "subject_code", ""), Map.get(course, "course_number", "")]
    |> Enum.reject(&blank?/1)
    |> Enum.join(" ")
  end

  def parse_course_input(value) when is_binary(value) do
    value = String.trim(value)

    cond do
      value == "" ->
        {"", ""}

      Regex.match?(~r/^\d[\w-]*$/, value) ->
        {"", value}

      true ->
        normalized =
          value
          |> String.replace(~r/\s*-\s*/, " ")
          |> String.replace(~r/^([A-Za-z]+)(\d.*)$/, "\\1 \\2")

        case String.split(normalized, ~r/\s+/, parts: 2, trim: true) do
          [subject_code, course_number] ->
            {String.upcase(subject_code), String.trim(course_number)}

          [subject_code] ->
            {String.upcase(subject_code), ""}

          _ ->
            {"", ""}
        end
    end
  end

  def parse_course_input(%{} = value) do
    value
    |> flatten_input_value()
    |> parse_course_input()
  end

  def course_suggestions(courses, query, limit \\ @max_suggestions)
      when is_list(courses) and is_integer(limit) do
    normalized_query = normalize(query)

    if normalized_query == "" do
      []
    else
      courses
      |> Enum.uniq_by(fn course ->
        {
          normalize(Map.get(course, "subject_code", "")),
          normalize(Map.get(course, "course_number", ""))
        }
      end)
      |> Enum.map(&course_option/1)
      |> Enum.filter(fn option ->
        fuzzy_match?(normalized_query, option.search_text)
      end)
      |> Enum.sort_by(fn option ->
        {String.downcase(option.value), String.downcase(option.label)}
      end)
      |> Enum.take(limit)
    end
  end

  defp course_option(course) do
    value = course_input_value(course)
    label = Map.get(course, "name", "")

    %{
      value: value,
      label: label,
      search_text: normalize("#{value} #{label}")
    }
  end

  defp fuzzy_match?("", _target), do: true

  defp fuzzy_match?(search, target) do
    match_subsequence?(String.graphemes(search), String.graphemes(target))
  end

  defp match_subsequence?([], _target), do: true
  defp match_subsequence?(_search, []), do: false

  defp match_subsequence?([char | search_rest], [char | target_rest]),
    do: match_subsequence?(search_rest, target_rest)

  defp match_subsequence?(search, [_char | target_rest]),
    do: match_subsequence?(search, target_rest)

  defp normalize(value) when is_binary(value) do
    value
    |> String.downcase()
    |> String.replace(~r/\s+/, "")
  end

  defp normalize(_value), do: ""

  defp blank?(value), do: not is_binary(value) or String.trim(value) == ""

  defp flatten_input_value(%{} = value) do
    value
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.find_value("", fn {_key, nested} ->
      cond do
        is_binary(nested) -> nested
        is_map(nested) -> flatten_input_value(nested)
        true -> nil
      end
    end)
  end
end
