defmodule SnowSeToolsWeb.Discord.DiscordGraduationHelpersTest do
  use ExUnit.Case, async: true

  alias SnowSeToolsWeb.Discord.DiscordGraduationHelpers

  test "returns the recommended channel group id for a mapped course" do
    channel_groups = [
      %{id: "group-1", name: "class of 2030(MAY)"},
      %{id: "group-2", name: "class of 2027(MAY)"}
    ]

    assert {:ok, "group-1"} =
             DiscordGraduationHelpers.recommended_channel_group_id(
               subject: "CS",
               course_number: "1410",
               term_code: "202640",
               channel_groups: channel_groups
             )
  end

  test "matches graduation channel groups despite spacing and case differences" do
    channel_groups = [
      %{id: "group-1", name: "Class Of 2030 (May)"}
    ]

    assert {:ok, "group-1"} =
             DiscordGraduationHelpers.recommended_channel_group_id(
               subject: "CS",
               course_number: "1410",
               term_code: "202640",
               channel_groups: channel_groups
             )
  end

  test "summer terms are skipped when determining the recommended cohort" do
    channel_groups = [
      %{id: "group-1", name: "class of 2026(DEC)"}
    ]

    assert {:ok, "group-1"} =
             DiscordGraduationHelpers.recommended_channel_group_id(
               subject: "SE",
               course_number: "4230",
               term_code: "202610",
               channel_groups: channel_groups
             )
  end

  test "returns channel_group_not_found when the mapped cohort is absent" do
    channel_groups = [
      %{id: "group-2", name: "class of 2027(MAY)"}
    ]

    assert {:error, :channel_group_not_found} =
             DiscordGraduationHelpers.recommended_channel_group_id(
               subject: "CS",
               course_number: "1410",
               term_code: "202640",
               channel_groups: channel_groups
             )
  end

  test "returns course_not_configured for unmapped courses" do
    assert {:error, :course_not_configured} =
             DiscordGraduationHelpers.recommended_channel_group_id(
               subject: "SE",
               course_number: "9999",
               term_code: "202640",
               channel_groups: []
             )
  end

  test "returns invalid_term_code for malformed terms" do
    assert {:error, :invalid_term_code} =
             DiscordGraduationHelpers.recommended_channel_group_id(
               subject: "SE",
               course_number: "4620",
               term_code: "bad",
               channel_groups: []
             )
  end
end
