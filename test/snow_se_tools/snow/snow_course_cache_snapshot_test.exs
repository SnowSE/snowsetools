defmodule SnowSeTools.Snow.SnowCourseCacheSnapshotTest do
  @moduledoc """
  The admin page's cached-semester list.

  The snapshot reaches a template that does `for course <- term["courses"]`, so
  a term whose courses are anything but a list takes the whole LiveView down
  with a Protocol.UndefinedError — a red banner, a reload, and a card that can
  never be expanded again. That is exactly what shipped when a `case` on a
  database read kept a catch-all clause after the read started answering
  `{:ok, rows}`.
  """
  use SnowSeToolsWeb.ConnCase, async: false

  alias SnowSeTools.Snow.{SnowCourseCacheDb, SnowCourseCacheDomainManager}

  setup do
    start_supervised!(SnowCourseCacheDomainManager)
    :ok
  end

  test "the dashboard snapshot carries each term's courses as a list" do
    term_code = seed_term()

    SnowCourseCacheDomainManager.request_dashboard(pid: self())

    assert_receive {:admin_ui_snow_cache_terms, terms}, 5_000

    term = Enum.find(terms, &(&1["term_code"] == term_code))
    assert term, "expected the seeded term in the snapshot"

    assert is_list(term["courses"]),
           "courses must be a list; got #{inspect(term["courses"], limit: 3)}"

    assert Enum.any?(term["courses"], &(&1["course_name"] == "Basic Income Tax Preparation"))

    # The template does exactly this, and a tuple here is what crashed the page.
    assert Enum.map(term["courses"], & &1["crn"]) != []
  end

  test "a term with nothing cached still comes back as an empty list" do
    {:ok, _} = SnowCourseCacheDb.upsert_term(term_code: empty_term(), term_name: "Empty Term")

    SnowCourseCacheDomainManager.request_dashboard(pid: self())

    assert_receive {:admin_ui_snow_cache_terms, terms}, 5_000
    assert Enum.all?(terms, &is_list(&1["courses"]))
  end

  defp seed_term do
    term_code = "2027#{System.unique_integer([:positive])}"

    :ok =
      SnowCourseCacheDb.save_courses(
        term_code: term_code,
        term_name: "Spring 2027",
        courses: [
          %{
            "crn" => "2451",
            "subject_code" => "ACCT",
            "course_number" => "1200",
            "section_number" => "001",
            "name" => "Basic Income Tax Preparation",
            "credit_hours" => 3,
            "instructors" => [%{"name" => "Carlie Fowles", "primary_instructor" => true}],
            "meet_info" => []
          }
        ]
      )

    term_code
  end

  defp empty_term, do: "2027#{System.unique_integer([:positive])}"
end
