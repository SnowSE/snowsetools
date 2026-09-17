defmodule SnowSeTools.Scheduling.TimeOfDay do
  @moduledoc """
  One reading of a clock time for the whole scheduling area.

  Banner hands us times as `"09:00"`, `"09:00:00"` and occasionally `"9:00"`.
  Parsing used to be written once per module and the copies disagreed: a
  single-digit hour came out as 540 minutes in the conflict detector, `nil` in
  the change manager and midnight on the week grid, with nothing to say which
  was right. Everything now goes through `parse/1`, which reads all three shapes
  and says plainly when it cannot read a value.
  """

  @week_days ["Monday", "Tuesday", "Wednesday", "Thursday", "Friday"]

  @doc "The teaching week, in display order."
  def week_days, do: @week_days

  def week_day?(day), do: day in @week_days

  @doc """
  Minutes past midnight for a clock time, or `:error` when the value is not one.

      iex> TimeOfDay.parse("09:30:00")
      {:ok, 570}
      iex> TimeOfDay.parse("9:30")
      {:ok, 570}
      iex> TimeOfDay.parse("later")
      :error
  """
  @spec parse(term()) :: {:ok, non_neg_integer()} | :error
  def parse(value) when is_binary(value) do
    case value |> String.trim() |> String.split(":") do
      [hour, minute | _seconds] -> from_parts(hour, minute)
      _not_a_clock_time -> :error
    end
  end

  def parse(_value), do: :error

  @doc """
  Minutes past midnight, falling back to `default` when the value cannot be
  read. Callers pass the fallback that makes sense where they stand, rather
  than inheriting one from whichever copy of the parser they happened to use.
  """
  @spec minutes(term(), fallback) :: non_neg_integer() | fallback when fallback: term()
  def minutes(value, default) do
    case parse(value) do
      {:ok, minutes} -> minutes
      :error -> default
    end
  end

  @doc ~S'A readable time as `"HH:MM"`, or `""` when it cannot be read.'
  def normalize(value) do
    case parse(value) do
      {:ok, minutes} -> format(minutes)
      :error -> ""
    end
  end

  @doc ~S'A readable time as `"HH:MM"`, or `nil` when it cannot be read.'
  def normalize_or_nil(value) do
    case parse(value) do
      {:ok, minutes} -> format(minutes)
      :error -> nil
    end
  end

  @doc ~S'`"09:30"` for minutes past midnight.'
  def format(minutes) when is_integer(minutes) do
    "#{pad(div(minutes, 60))}:#{pad(rem(minutes, 60))}"
  end

  @doc ~S'`"9:30 AM"` for minutes past midnight.'
  def format_12h(minutes) when is_integer(minutes) do
    hour = div(minutes, 60)
    period = if rem(hour, 24) >= 12, do: "PM", else: "AM"
    display_hour = hour |> rem(12) |> then(&if(&1 == 0, do: 12, else: &1))

    "#{display_hour}:#{pad(rem(minutes, 60))} #{period}"
  end

  @doc """
  Minutes from `start_time` to `end_time`, or `nil` when either cannot be read.
  """
  def duration(start_time, end_time) do
    with {:ok, start_minutes} <- parse(start_time),
         {:ok, end_minutes} <- parse(end_time) do
      end_minutes - start_minutes
    else
      :error -> nil
    end
  end

  defp from_parts(hour, minute) do
    with {hour, ""} <- hour |> String.trim() |> Integer.parse(),
         {minute, ""} <- minute |> String.trim() |> Integer.parse(),
         true <- hour in 0..23 and minute in 0..59 do
      {:ok, hour * 60 + minute}
    else
      _unreadable -> :error
    end
  end

  defp pad(value), do: value |> Integer.to_string() |> String.pad_leading(2, "0")
end
