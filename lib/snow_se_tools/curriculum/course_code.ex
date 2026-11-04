defmodule SnowSeTools.Curriculum.CourseCode do
  @moduledoc """
  Reads course codes out of free text: "CS 2450 and CS 2860", "MATH 1050 or
  1060", "Math 1210 and (either Math 2040 or Math 3040)", "CS  1410
  Object-Oriented Programming".
  """

  @token ~r/\b(?!(?i:or|and)\b)([A-Za-z]{2,4})\s*(\d{4})\b|(?:,|&|\/|\bor|\band)\s+(\d{4})\b/

  # Words that sit in front of a year the way a subject sits in front of a
  # course number ("Fall 2026"), so they are not read as subjects.
  @not_subjects ~w(FALL YEAR TERM SINCE FROM)

  @doc """
  Every course code mentioned in `text`, in order and without repeats. A bare
  number joined to a code by "or", "and", "," or "&" borrows that code's
  subject, so "MATH 1050 or 1060" yields both MATH courses while the year in
  "(Fall 2026)" is left alone.
  """
  def extract_all(text) when is_binary(text) do
    @token
    |> Regex.scan(text)
    |> Enum.reduce({nil, []}, fn
      [_full, subject, number], {last_subject, codes} ->
        subject = String.upcase(subject)

        if subject in @not_subjects,
          do: {last_subject, codes},
          else: {subject, [{subject, number} | codes]}

      [_full, "", "", number], {last_subject, codes} when is_binary(last_subject) ->
        {last_subject, [{last_subject, number} | codes]}

      _bare_number_without_subject, acc ->
        acc
    end)
    |> elem(1)
    |> Enum.reverse()
    |> Enum.uniq()
  end

  def extract_all(_text), do: []

  @doc "The first course code at the start of `text`, such as a spreadsheet column header."
  def parse_leading(text) when is_binary(text) do
    case Regex.run(~r/^\s*([A-Za-z]{2,4})\s*(\d{4})/, text) do
      [_full, subject, number] -> {:ok, {String.upcase(subject), number}}
      nil -> :error
    end
  end

  def parse_leading(_text), do: :error

  def label({subject, number}), do: "#{subject} #{number}"
  def label(%{"subject_code" => subject, "course_number" => number}), do: "#{subject} #{number}"

  def key(%{"subject_code" => subject, "course_number" => number}), do: {subject, number}
end
