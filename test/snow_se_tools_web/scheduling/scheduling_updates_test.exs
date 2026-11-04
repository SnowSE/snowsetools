defmodule SnowSeToolsWeb.Scheduling.SchedulingUpdatesTest do
  use SnowSeToolsWeb.ConnCase, async: false

  alias SnowSeTools.Data.User
  alias SnowSeToolsWeb.Scheduling.SchedulingUpdates

  setup do
    # The first user ever is made admin; keep that from being one of these.
    {:ok, _bootstrap} = User.find_or_create("updates-bootstrap@example.com")
    :ok
  end

  test "anyone who can read schedules can open Updates from the scheduling tabs", %{conn: conn} do
    conn = log_in_user(conn, "updates-viewer@example.com", ["scheduling_view"])
    {:ok, view, _html} = live(conn, ~p"/scheduling?mode=viewer")

    view |> element("#scheduling-tab-updates") |> render_click()

    assert_patch(view, ~p"/scheduling?mode=updates")
    assert has_element?(view, "#scheduling-updates h1", "What's new in scheduling")
    assert has_element?(view, "#conflict-badges")
  end

  test "editors can open it too", %{conn: conn} do
    conn = log_in_user(conn, "updates-editor@example.com", ["scheduling_admin"])
    {:ok, view, _html} = live(conn, ~p"/scheduling?mode=updates")

    assert has_element?(view, "#review-program-conflicts")
  end

  test "someone without scheduling access can't", %{conn: conn} do
    conn = log_in_user(conn, "updates-outsider@example.com", ["syllabus_admin"])

    assert {:error, {_redirect, %{to: to}}} = live(conn, ~p"/scheduling?mode=updates")
    refute to =~ "/scheduling"
  end

  test "every feature has a unique anchor and every screenshot is there" do
    features = Enum.flat_map(SchedulingUpdates.releases(), & &1.features)
    ids = Enum.map(features, & &1.id)

    assert ids == Enum.uniq(ids)

    for feature <- features, image <- feature.images do
      path = Path.join("priv/static", SchedulingUpdates.image_path(image))
      assert File.exists?(path), "missing screenshot #{path}"
      assert image.alt != ""
    end
  end
end
