defmodule SnowSeToolsWeb.Admin.AiSettingsTest do
  @moduledoc """
  The AI server box on the admin page. What matters: saving a model takes
  effect without a redeploy, the stored API key never travels back to the
  browser, and an admin can put a field back on the environment value.
  """
  use SnowSeToolsWeb.ConnCase, async: false

  alias SnowSeTools.AI.{Settings, SettingsDb, SettingsDomainManager}

  setup do
    start_supervised!(SettingsDomainManager)
    original = Application.get_env(:snow_se_tools, :ai, [])

    Application.put_env(:snow_se_tools, :ai,
      endpoint: "https://env.example/v1/chat/completions",
      api_key: "env-key",
      model: "env-model"
    )

    clear_all()

    on_exit(fn ->
      clear_all()
      Application.put_env(:snow_se_tools, :ai, original)
    end)

    :ok
  end

  test "saving a model changes what the next completion will use", %{conn: conn} do
    {:ok, view, _html} = live(log_in_admin(conn), ~p"/admin")
    settle(view)

    html = save(view, %{"model" => "qwen3-32k"})

    assert html =~ "AI settings saved."
    assert Settings.current()[:model] == "qwen3-32k"
  end

  test "a saved API key is never rendered back to the page", %{conn: conn} do
    {:ok, view, _html} = live(log_in_admin(conn), ~p"/admin")
    settle(view)

    html = save(view, %{"api_key" => "super-secret-key"})

    refute html =~ "super-secret-key"
    assert Settings.current()[:api_key] == "super-secret-key"
  end

  test "saving other fields with the key box blank keeps the stored key", %{conn: conn} do
    {:ok, _} = SettingsDb.put(%{api_key: "keep-me"}, updated_by: "someone@example.com")

    {:ok, view, _html} = live(log_in_admin(conn), ~p"/admin")
    settle(view)

    save(view, %{"model" => "another-model", "api_key" => ""})

    assert Settings.current()[:api_key] == "keep-me"
    assert Settings.current()[:model] == "another-model"
  end

  test "reverting a field puts it back on the environment value", %{conn: conn} do
    {:ok, view, _html} = live(log_in_admin(conn), ~p"/admin")
    settle(view)

    save(view, %{"model" => "temporary"})
    assert Settings.current()[:model] == "temporary"

    view
    |> element(~s(#ai-settings-component button[phx-value-field="model"]))
    |> render_click()

    settle(view)

    assert Settings.current()[:model] == "env-model"
  end

  test "a crafted revert for an unknown field is refused, not crashed on", %{conn: conn} do
    {:ok, view, _html} = live(log_in_admin(conn), ~p"/admin")
    settle(view)

    view
    |> with_target("#ai-settings-component")
    |> render_click("clear_ai_override", %{"field" => "secret_key_base"})

    settle(view)

    assert render(view) =~ "That is not an AI setting."
  end

  test "a non-admin cannot reach the page at all", %{conn: conn} do
    conn = log_in_user(conn, unique_email("ai-settings-viewer"), ["syllabus_admin"])

    assert {:error, {:redirect, _}} = live(conn, ~p"/admin")
  end

  defp save(view, fields) do
    params = Map.merge(%{"endpoint" => "", "model" => "", "api_key" => ""}, fields)

    view
    |> form("#admin-ai-settings-form", %{"ai" => params})
    |> render_submit()

    settle(view)
  end

  # The save runs through a cast to the domain manager, which answers the
  # LiveView with a message of its own.
  defp settle(view) do
    _ = :sys.get_state(SettingsDomainManager)
    _ = :sys.get_state(view.pid)
    render(view)
  end

  defp clear_all do
    {:ok, _} =
      SettingsDb.put(%{endpoint: nil, model: nil, api_key: nil}, updated_by: "test-reset")
  end

  defp log_in_admin(conn), do: log_in_user(conn, unique_email("ai-settings-admin"), ["admin"])
end
