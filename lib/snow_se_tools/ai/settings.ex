defmodule SnowSeTools.AI.Settings do
  @moduledoc """
  The AI endpoint, model and key actually in force: what an admin saved on the
  admin page, falling back field by field to what the environment set.

  Resolution happens per call rather than at boot, so changing the server or
  model on the admin page takes effect on the next completion instead of on the
  next deploy. A completion is a network round trip measured in seconds, so one
  extra query is not worth caching -- and a cache would be the thing that makes
  "I changed it and nothing happened" possible.

  Every read falls back to the environment if the database cannot answer. A
  database that is down should not also take the AI down, and during boot the
  table may not exist yet.
  """

  require Logger

  alias SnowSeTools.AI.SettingsDb

  @doc """
  The effective config, shaped like the `:ai` application env the call sites
  already expect: `[endpoint: ..., api_key: ..., model: ...]`.
  """
  def current do
    overrides = stored()

    Enum.map([:endpoint, :api_key, :model], fn field ->
      {field, override(overrides, field) || env()[field]}
    end)
  end

  @doc """
  What the admin page shows: the effective value of each field and whether it
  came from the database or the environment.

  The API key is never included. A write-only field is only write-only if its
  value does not travel back out to a browser, so the page gets
  `api_key_source` and nothing else -- enough to say "an override is set"
  without being enough to read it.
  """
  def summary do
    overrides = stored()

    %{
      endpoint: override(overrides, :endpoint) || env()[:endpoint],
      model: override(overrides, :model) || env()[:model],
      endpoint_source: source(overrides, :endpoint),
      model_source: source(overrides, :model),
      api_key_source: source(overrides, :api_key),
      env_endpoint: env()[:endpoint],
      env_model: env()[:model],
      updated_by: overrides["updated_by"],
      updated_at: overrides["updated_at"]
    }
  end

  defp source(overrides, field) do
    if override(overrides, field), do: :database, else: :environment
  end

  defp override(overrides, field) do
    case Map.get(overrides, Atom.to_string(field)) do
      value when is_binary(value) ->
        case String.trim(value) do
          "" -> nil
          trimmed -> trimmed
        end

      _ ->
        nil
    end
  end

  defp stored do
    case SettingsDb.get() do
      {:ok, overrides} ->
        overrides

      {:error, reason} ->
        Logger.warning("AI settings unreadable, using environment: #{inspect(reason)}")
        %{}
    end
  rescue
    error ->
      Logger.warning("AI settings unreadable, using environment: #{inspect(error)}")
      %{}
  end

  defp env, do: Application.get_env(:snow_se_tools, :ai, [])
end
