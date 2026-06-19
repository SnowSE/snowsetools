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
        search_fields = [
          normalize(option.value),
          normalize(option.label),
          normalize(Map.get(option, :subject_code, "")),
          normalize(Map.get(option, :course_number, ""))
        ]

        Enum.any?(search_fields, &String.contains?(&1, normalized_query))
      end)
      |> Enum.sort_by(fn option ->
        subject_code = normalize(Map.get(option, :subject_code, ""))
        course_number = normalize(Map.get(option, :course_number, ""))
        value = normalize(option.value)

        subject_match? = String.contains?(subject_code, normalized_query)
        number_match? = String.contains?(course_number, normalized_query)
        value_match? = String.contains?(value, normalized_query)

        priority =
          cond do
            subject_match? -> 0
            number_match? -> 1
            value_match? -> 2
            true -> 3
          end

        {priority, String.downcase(option.value), String.downcase(option.label)}
      end)
      |> Enum.take(limit)
    end
  end

  defp course_option(course) do
    value = course_input_value(course)
    label = Map.get(course, "name", "")
    subject_code = Map.get(course, "subject_code", "")
    course_number = Map.get(course, "course_number", "")

    %{
      value: value,
      label: label,
      subject_code: subject_code,
      course_number: course_number,
      search_text: normalize("#{value} #{label}")
    }
  end

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
