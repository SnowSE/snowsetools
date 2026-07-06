defmodule SnowSeToolsWeb.Discord.DiscordGraduationHelpersTest do
  use ExUnit.Case, async: true

  alias SnowSeToolsWeb.Discord.DiscordGraduationHelpers

  test "freshman fall CS course resolves to spring 2030 cohort" do
    assert {:ok,
            %{
              terms_away: 7,
              graduation_term_code: "203010",
              graduation_year: 2030,
              graduation_month: "MAY",
              role_name: "may_30",
              channel_group_name: "class of 2030(MAY)"
            }} =
             DiscordGraduationHelpers.graduation_target(
               subject: "CS",
               course_number: "1410",
               term_code: "202640"
             )
  end

  test "senior spring SE course resolves to same-term graduation cohort" do
    assert {:ok,
            %{
              terms_away: 0,
              graduation_term_code: "202710",
              graduation_year: 2027,
              graduation_month: "MAY",
              role_name: "may_27",
              channel_group_name: "class of 2027(MAY)"
            }} =
             DiscordGraduationHelpers.graduation_target(
               subject: "SE",
               course_number: "4620",
               term_code: "202710"
             )
  end

  test "auto selection matches role and channel group names when they exist" do
    roles = [
      %{"id" => "role-1", "name" => "may_30"},
      %{"id" => "role-2", "name" => "may_27"}
    ]

    channel_groups = [
      %{id: "group-1", name: "class of 2030(MAY)"},
      %{id: "group-2", name: "class of 2027(MAY)"}
    ]

    assert {:ok,
            %{
              role_id: "role-1",
              channel_group_id: "group-1",
              role_name: "may_30",
              channel_group_name: "class of 2030(MAY)"
            }} =
             DiscordGraduationHelpers.auto_selection(
               subject: "CS",
               course_number: "1410",
               term_code: "202640",
               roles: roles,
               channel_groups: channel_groups
             )
  end

  test "summer terms are skipped when advancing toward graduation" do
    assert {:ok,
            %{
              terms_away: 1,
              graduation_term_code: "202640",
              graduation_year: 2026,
              graduation_month: "DEC",
              role_name: "dec_26",
              channel_group_name: "class of 2026(DEC)"
            }} =
             DiscordGraduationHelpers.graduation_target(
               subject: "SE",
               course_number: "4230",
               term_code: "202610"
             )
  end

  test "returns course_not_configured for unmapped courses" do
    assert {:error, :course_not_configured} =
             DiscordGraduationHelpers.graduation_target(
               subject: "SE",
               course_number: "9999",
               term_code: "202640"
             )
  end
end
