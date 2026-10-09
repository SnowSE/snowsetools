defmodule SnowSeTools.Curriculum.TermLabel do
  @moduledoc """
  Finds the academic term in a label written however its author felt like it:
  "Fall 2026", "2026-fall-dallan", "2026_spring_adam", "adam2023_fall",
  "2022Spring", or just "2026".
  """

  @seasons %{"winter" => 0, "spring" => 1, "summer" => 2, "fall" => 3}

  @doc """
  `{:ok, {year, season_rank}}` for a label that names a year, where the rank
  orders seasons within the year and is `nil` when only the year is given.
  `:error` when the label names no year at all.
  """
  def parse(label) when is_binary(label) do
    lowered = String.downcase(label)

    case Regex.run(~r/(?<!\d)(20\d\d)(?!\d)/, lowered) do
      [_full, year] -> {:ok, {String.to_integer(year), season_rank(lowered)}}
      nil -> :error
    end
  end

  def parse(_label), do: :error

  @doc """
  Sort key, newest last. A year-only label sorts after every season of that
  year: a folder named "2026" was most likely made for the newest work.
  """
  def sort_key({year, nil}), do: {year, 9}
  def sort_key({year, rank}), do: {year, rank}

  @doc """
  From `items`, the ones whose label falls in the `count` most recent distinct
  terms. Several items can share a term (two instructors teaching the same
  course in Fall 2026), and all of them are kept.
  """
  def latest(items: items, count: count, label: label_fun)
      when is_list(items) and is_function(label_fun, 1) do
    dated =
      for item <- items, {:ok, term} <- [parse(label_fun.(item))] do
        {sort_key(term), item}
      end

    newest_terms =
      dated
      |> Enum.map(&elem(&1, 0))
      |> Enum.uniq()
      |> Enum.sort(:desc)
      |> Enum.take(count)
      |> MapSet.new()

    dated
    |> Enum.filter(fn {term, _item} -> MapSet.member?(newest_terms, term) end)
    |> Enum.sort_by(&elem(&1, 0), :desc)
    |> Enum.map(&elem(&1, 1))
  end

  defp season_rank(lowered) do
    Enum.find_value(@seasons, fn {season, rank} ->
      if String.contains?(lowered, season), do: rank
    end)
  end
end
