defmodule SnowSeTools.AI.SettingsDomainManager do
  @moduledoc """
  Coordinates reads and writes of the AI endpoint/model/key overrides for the
  admin page.

  Like the other domain managers this creates its own table at boot, so
  switching AI servers needs no migration step.
  """

  use GenServer

  require Logger

  alias SnowSeTools.AI.{Settings, SettingsDb}
  alias SnowSeToolsWeb.Admin.AdminUIMessages

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def request_settings(pid: pid) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:request_settings, pid})
  end

  def save_settings(pid: pid, params: params, user: user) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:save_settings, pid, params, user})
  end

  def clear_override(pid: pid, field: field, user: user) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:clear_override, pid, field, user})
  end

  @impl true
  def init(:ok) do
    case SettingsDb.bootstrap_tables() do
      :ok -> {:ok, %{}}
      {:error, reason} -> {:stop, {:query_failed, reason}}
    end
  end

  @impl true
  def handle_cast({:request_settings, pid}, state) do
    AdminUIMessages.send_ai_settings(pid: pid, settings: Settings.summary())
    {:noreply, state}
  end

  def handle_cast({:save_settings, pid, params, user}, state) do
    changes = changes_from(params)

    if changes == %{} do
      AdminUIMessages.send_action_result(pid: pid, result: {:ok, "Nothing to change."})
    else
      write(pid, changes, user, "AI settings saved.")
    end

    {:noreply, state}
  end

  # `field` arrives from a phx-value- attribute, so it is whatever the client
  # sent. Matching it against the known names rather than converting it to an
  # atom keeps a crafted event from crashing the page.
  def handle_cast({:clear_override, pid, field, user}, state) do
    case Enum.find(SettingsDb.fields(), &(Atom.to_string(&1) == to_string(field))) do
      nil ->
        AdminUIMessages.send_action_result(pid: pid, result: {:error, :unknown_ai_setting})

      known ->
        write(pid, %{known => nil}, user, "Reverted to the environment value.")
    end

    {:noreply, state}
  end

  defp write(pid, changes, user, message) do
    case SettingsDb.put(changes, updated_by: identify(user)) do
      {:ok, _row} ->
        AdminUIMessages.send_ai_settings(pid: pid, settings: Settings.summary())
        AdminUIMessages.send_action_result(pid: pid, result: {:ok, message})

      {:error, reason} ->
        Logger.error("Saving AI settings failed: #{inspect(reason)}")
        AdminUIMessages.send_action_result(pid: pid, result: {:error, reason})
    end
  end

  # An omitted field keeps whatever is stored; a blank one is treated the same
  # way. Clearing an override is "Use environment value", never an empty box --
  # otherwise an admin editing only the model would silently wipe the API key,
  # which the form never shows them in the first place.
  defp changes_from(params) do
    SettingsDb.fields()
    |> Enum.reduce(%{}, fn field, changes ->
      case params |> Map.get(Atom.to_string(field)) |> trimmed() do
        nil -> changes
        value -> Map.put(changes, field, value)
      end
    end)
  end

  defp trimmed(value) when is_binary(value) do
    case String.trim(value) do
      "" -> nil
      trimmed -> trimmed
    end
  end

  defp trimmed(_), do: nil

  defp identify(%{"email" => email}) when is_binary(email), do: email
  defp identify(%{email: email}) when is_binary(email), do: email
  defp identify(_), do: "unknown"
end
