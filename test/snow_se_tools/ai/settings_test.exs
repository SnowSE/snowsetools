defmodule SnowSeTools.AI.SettingsTest do
  @moduledoc """
  The AI endpoint, model and key resolve field by field: a stored override
  wins, and anything not overridden still follows the environment.

  `ai_settings` holds a single row, so these tests share one piece of global
  state. Every test clears it again on the way out, and nothing here asserts on
  what the environment happens to be set to beyond the values it sets itself.
  """
  use SnowSeToolsWeb.ConnCase, async: false

  alias SnowSeTools.AI.{Settings, SettingsDb}

  setup do
    :ok = SettingsDb.bootstrap_tables()
    original = Application.get_env(:snow_se_tools, :ai, [])

    Application.put_env(:snow_se_tools, :ai,
      endpoint: "https://env.example/v1/chat/completions",
      api_key: "env-key",
      model: "env-model"
    )

    on_exit(fn ->
      clear_all()
      Application.put_env(:snow_se_tools, :ai, original)
    end)

    :ok
  end

  test "with nothing stored, every field comes from the environment" do
    clear_all()

    config = Settings.current()

    assert config[:endpoint] == "https://env.example/v1/chat/completions"
    assert config[:api_key] == "env-key"
    assert config[:model] == "env-model"
    assert Settings.summary().model_source == :environment
  end

  test "a stored model overrides the environment without disturbing the rest" do
    clear_all()
    {:ok, _} = SettingsDb.put(%{model: "qwen3-32k"}, updated_by: "admin@example.com")

    config = Settings.current()

    assert config[:model] == "qwen3-32k"
    assert config[:endpoint] == "https://env.example/v1/chat/completions"
    assert config[:api_key] == "env-key"
  end

  test "an omitted field keeps the override already stored" do
    clear_all()
    {:ok, _} = SettingsDb.put(%{api_key: "stored-key"}, updated_by: "admin@example.com")
    {:ok, _} = SettingsDb.put(%{model: "other-model"}, updated_by: "admin@example.com")

    config = Settings.current()

    assert config[:api_key] == "stored-key"
    assert config[:model] == "other-model"
  end

  test "writing nil clears an override back to the environment" do
    clear_all()
    {:ok, _} = SettingsDb.put(%{model: "temporary"}, updated_by: "admin@example.com")
    assert Settings.current()[:model] == "temporary"

    {:ok, _} = SettingsDb.put(%{model: nil}, updated_by: "admin@example.com")

    assert Settings.current()[:model] == "env-model"
    assert Settings.summary().model_source == :environment
  end

  test "a blank string is stored as no override rather than as an empty endpoint" do
    clear_all()
    {:ok, _} = SettingsDb.put(%{endpoint: "   "}, updated_by: "admin@example.com")

    assert Settings.current()[:endpoint] == "https://env.example/v1/chat/completions"
    assert Settings.summary().endpoint_source == :environment
  end

  test "the summary says where each field came from and never carries the key" do
    clear_all()

    {:ok, _} =
      SettingsDb.put(%{endpoint: "https://stored.example/v1", api_key: "secret-key"},
        updated_by: "admin@example.com"
      )

    summary = Settings.summary()

    assert summary.endpoint == "https://stored.example/v1"
    assert summary.endpoint_source == :database
    assert summary.api_key_source == :database
    assert summary.model_source == :environment
    assert summary.updated_by == "admin@example.com"

    refute summary |> Map.values() |> Enum.any?(&(&1 == "secret-key"))
    refute Map.has_key?(summary, :api_key)
  end

  test "saving twice updates the one row instead of adding another" do
    clear_all()
    {:ok, _} = SettingsDb.put(%{model: "first"}, updated_by: "one@example.com")
    {:ok, _} = SettingsDb.put(%{model: "second"}, updated_by: "two@example.com")

    {:ok, stored} = SettingsDb.get()

    assert stored["model"] == "second"
    assert stored["updated_by"] == "two@example.com"
  end

  defp clear_all do
    {:ok, _} =
      SettingsDb.put(%{endpoint: nil, model: nil, api_key: nil}, updated_by: "test-reset")
  end
end
