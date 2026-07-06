defmodule SnowSeToolsWeb.Discord.DiscordGraduationHelpers do
  @moduledoc false

  @course_terms_away_from_graduation %{
    {"CS", "1410"} => 7,
    {"CS", "1415"} => 7,
    {"CS", "1430"} => 7,
    {"CS", "1810"} => 6,
    {"CS", "2420"} => 5,
    {"CS", "2810"} => 5,
    {"CS", "2450"} => 4,
    {"CS", "2860"} => 4,
    {"SE", "3250"} => 3,
    {"SE", "3520"} => 3,
    {"SE", "3820"} => 3,
    {"SE", "3140"} => 2,
    {"SE", "3630"} => 2,
    {"SE", "3830"} => 2,
    {"SE", "3840"} => 2,
    {"SE", "4230"} => 1,
    {"SE", "4270"} => 1,
    {"SE", "4400"} => 1,
    {"SE", "4850"} => 1,
    {"SE", "4340"} => 0,
    {"SE", "4450"} => 0,
    {"SE", "4620"} => 0
  }

  def recommended_channel_group_id(
        subject: subject,
        course_number: course_number,
        term_code: term_code,
        channel_groups: channel_groups
      ) do
    normalized_group_names =
      Map.new(channel_groups, fn group ->
        {normalize_channel_group_name(group.name), group.id}
      end)

    with {:ok, target} <-
           graduation_target(subject: subject, course_number: course_number, term_code: term_code),
         group_id when is_binary(group_id) <-
           Map.get(
             normalized_group_names,
             normalize_channel_group_name(target.channel_group_name)
           ) do
      {:ok, group_id}
    else
      {:error, reason} -> {:error, reason}
      nil -> {:error, :channel_group_not_found}
    end
  end

  defp graduation_target(subject: subject, course_number: course_number, term_code: term_code) do
    normalized_subject = normalize_subject(subject)
    normalized_course_number = normalize_course_number(course_number)

    with {:ok, terms_away} <-
           terms_away_from_graduation(
             subject: normalized_subject,
             course_number: normalized_course_number
           ),
         {:ok, graduation_term_code} <- add_terms(term_code: term_code, term_count: terms_away),
         {:ok, graduation_label} <- graduation_label(term_code: graduation_term_code) do
      {:ok,
       %{
         subject: normalized_subject,
         course_number: normalized_course_number,
         terms_away: terms_away,
         graduation_term_code: graduation_term_code,
         graduation_year: graduation_label.year,
         graduation_month: graduation_label.month,
         role_name: graduation_role_name(graduation_label: graduation_label),
         channel_group_name: graduation_channel_group_name(graduation_label: graduation_label)
       }}
    end
  end

  defp terms_away_from_graduation(subject: subject, course_number: course_number) do
    case Map.fetch(
           @course_terms_away_from_graduation,
           {normalize_subject(subject), normalize_course_number(course_number)}
         ) do
      {:ok, term_count} -> {:ok, term_count}
      :error -> {:error, :course_not_configured}
    end
  end

  defp add_terms(term_code: term_code, term_count: term_count)
       when is_binary(term_code) and is_integer(term_count) and term_count >= 0 do
    with {:ok, year, season_code} <- parse_term_code(term_code: term_code) do
      {:ok, advance_term(year: year, season_code: season_code, remaining_terms: term_count)}
    end
  end

  defp add_terms(term_code: _term_code, term_count: _term_count), do: {:error, :invalid_term_code}

  defp graduation_label(term_code: term_code) do
    with {:ok, year, season_code} <- parse_term_code(term_code: term_code),
         {:ok, month} <- graduation_month(season_code: season_code) do
      {:ok, %{year: year, month: month}}
    end
  end

  defp graduation_month(season_code: "10"), do: {:ok, "MAY"}
  defp graduation_month(season_code: "30"), do: {:ok, "AUG"}
  defp graduation_month(season_code: "40"), do: {:ok, "DEC"}
  defp graduation_month(season_code: _season_code), do: {:error, :invalid_term_code}

  defp graduation_role_name(graduation_label: %{month: month, year: year}) do
    month
    |> String.downcase()
    |> Kernel.<>("_" <> String.slice(Integer.to_string(year), -2, 2))
  end

  defp graduation_channel_group_name(graduation_label: %{month: month, year: year}) do
    "class of #{year}(#{month})"
  end

  defp parse_term_code(term_code: term_code)
       when is_binary(term_code) and byte_size(term_code) == 6 do
    year_text = String.slice(term_code, 0, 4)
    season_code = String.slice(term_code, 4, 2)

    with {year, ""} <- Integer.parse(year_text),
         true <- season_code in ["10", "30", "40"] do
      {:ok, year, season_code}
    else
      _invalid -> {:error, :invalid_term_code}
    end
  end

  defp parse_term_code(term_code: _term_code), do: {:error, :invalid_term_code}

  defp advance_term(year: year, season_code: season_code, remaining_terms: 0) do
    Integer.to_string(year) <> season_code
  end

  defp advance_term(year: year, season_code: season_code, remaining_terms: remaining_terms) do
    {next_year, next_season_code} = next_academic_term(year: year, season_code: season_code)

    advance_term(
      year: next_year,
      season_code: next_season_code,
      remaining_terms: remaining_terms - 1
    )
  end

  defp next_academic_term(year: year, season_code: "10"), do: {year, "40"}
  defp next_academic_term(year: year, season_code: "30"), do: {year, "40"}
  defp next_academic_term(year: year, season_code: "40"), do: {year + 1, "10"}

  defp normalize_subject(subject) when is_binary(subject),
    do: subject |> String.trim() |> String.upcase()

  defp normalize_subject(_subject), do: ""

  defp normalize_course_number(course_number) when is_binary(course_number) do
    course_number
    |> String.trim()
    |> String.replace(~r/\s+/, "")
    |> String.upcase()
  end

  defp normalize_course_number(_course_number), do: ""

  defp normalize_channel_group_name(name) when is_binary(name) do
    name
    |> String.trim()
    |> String.downcase()
    |> String.replace(~r/[^a-z0-9]+/, "")
  end

  defp normalize_channel_group_name(_name), do: ""
end
