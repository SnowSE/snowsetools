defmodule SnowSeToolsWeb.Syllabus.SyllabusLiveTest do
  use ExUnit.Case, async: true

  alias SnowSeToolsWeb.Syllabus.SyllabusLive

  test "mode_from_params defaults to search" do
    assert SyllabusLive.mode_from_params(%{}) == :search
    assert SyllabusLive.mode_from_params(%{"mode" => "not-real"}) == :search
  end

  test "mode_from_params parses known modes" do
    assert SyllabusLive.mode_from_params(%{"mode" => "search"}) == :search
    assert SyllabusLive.mode_from_params(%{"mode" => "school_overviews"}) == :school_overviews
    assert SyllabusLive.mode_from_params(%{"mode" => "required_elements"}) == :required_elements
    assert SyllabusLive.mode_from_params(%{"mode" => "ai_history"}) == :ai_history
    assert SyllabusLive.mode_from_params(%{"mode" => "settings"}) == :settings
  end

  test "syllabus_path preserves existing params and updates the mode" do
    path =
      SyllabusLive.syllabus_path(params: %{"q" => "hello", "term" => "2024"}, mode: :ai_history)

    assert path == "/syllabi?mode=ai_history&q=hello&term=2024"
  end
end
