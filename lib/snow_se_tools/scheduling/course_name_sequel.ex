defmodule SnowSeTools.Scheduling.CourseNameSequel do
  @roman_numerals MapSet.new([
                    "i",
                    "ii",
                    "iii",
                    "iv",
                    "v",
                    "vi",
                    "vii",
                    "viii",
                    "ix",
                    "x",
                    "xi",
                    "xii",
                    "xiv",
                    "xv",
                    "xix",
                    "xx"
                  ])

  def course_pair_sequel_level?(name_a, name_b) when is_binary(name_a) and is_binary(name_b) do
    with {:ok, %{base: base, suffix_value: value_a}} <- parse_canonical(name_a),
         {:ok, %{base: ^base, suffix_value: value_b}} <- parse_canonical(name_b) do
      value_a != value_b
    else
      _ -> false
    end
  end

  def all_same_sequel_base?([]), do: {:error, :not_sequel_level}
  def all_same_sequel_base?([_]), do: {:error, :not_sequel_level}

  def all_same_sequel_base?(names) when is_list(names) do
    with {:ok, first = %{base: base}} <- parse_canonical(hd(names)),
         true <- Enum.all?(tl(names), &match?({:ok, %{base: ^base}}, parse_canonical(&1))) do
      suffix_values =
        names
        |> Enum.map(fn name ->
          {:ok, parsed} = parse_canonical(name)
          parsed.suffix_value
        end)

      if MapSet.size(MapSet.new(suffix_values)) == length(names) do
        {:ok, first.base}
      else
        {:error, :not_sequel_level}
      end
    else
      _ -> {:error, :not_sequel_level}
    end
  end

  def is_numeric_token?(token) do
    case Integer.parse(token) do
      {value, ""} -> valid_sequel_level?(value)
      _ -> token in @roman_numerals
    end
  end

  defp valid_sequel_level?(value) when is_integer(value), do: value in 1..50

  defp parse_canonical(name) do
    tokens = String.downcase(name) |> String.split(~r/\s+/, trim: true)

    if Enum.empty?(tokens) do
      {:error, :empty_name}
    else
      numeric_indices = find_numeric_token_indices(tokens)

      case numeric_indices do
        [idx] ->
          suffix = Enum.at(tokens, idx)
          value = to_numeric_value(suffix)
          base_tokens = List.replace_at(tokens, idx, "*") |> Enum.join(" ")
          {:ok, %{base: base_tokens, suffix: suffix, suffix_value: value}}

        _other ->
          {:error, :no_unique_numeric_suffix}
      end
    end
  end

  defp find_numeric_token_indices(tokens) do
    tokens
    |> Enum.with_index()
    |> Enum.reduce([], fn {token, idx}, acc ->
      if is_numeric_token?(token), do: [idx | acc], else: acc
    end)
  end

  defp to_numeric_value(token) do
    case Integer.parse(token) do
      {value, ""} -> value
      _ -> roman_to_integer(token) || 0
    end
  end

  defp roman_to_integer("i"), do: 1
  defp roman_to_integer("ii"), do: 2
  defp roman_to_integer("iii"), do: 3
  defp roman_to_integer("iv"), do: 4
  defp roman_to_integer("v"), do: 5
  defp roman_to_integer("vi"), do: 6
  defp roman_to_integer("vii"), do: 7
  defp roman_to_integer("viii"), do: 8
  defp roman_to_integer("ix"), do: 9
  defp roman_to_integer("x"), do: 10
  defp roman_to_integer("xi"), do: 11
  defp roman_to_integer("xii"), do: 12
  defp roman_to_integer("xiv"), do: 14
  defp roman_to_integer("xv"), do: 15
  defp roman_to_integer("xix"), do: 19
  defp roman_to_integer("xx"), do: 20
  defp roman_to_integer(_unknown), do: nil
end
