defmodule SnowSeToolsWeb.Scheduling.SchedulingAccess do
  @moduledoc """
  The one gate between a scheduling viewer and every event that changes
  something.

  Events are classified by namespace: a namespace is read-only for viewers or
  it is editor-only, with a short list of named exceptions. A namespace nobody
  has classified is denied and logged, so an event added later is blocked until
  someone decides it is safe rather than quietly allowed.

  Editors never meet the gate — the hook is only attached for viewers.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, put_flash: 3]

  require Logger

  alias SnowSeTools.Data.Access

  # Namespaces that only ever move the viewer's own window onto the data:
  # searching, selecting, arranging, resizing and saving personal layouts.
  @view_namespaces ~w(
    schedule-viewer
    schedule-owner-search
    schedule-owner-week-schedule
    schedule-details-order
    schedule-layouts
  )

  # Namespaces that write a course, a change group or a program.
  @editor_namespaces ~w(
    academic-programs
    academic-programs-editor
    academic-programs-picker
    schedule-change-groups
    week-schedule-grid
  )

  # Editor-only namespaces have a few events that read rather than write.
  @view_events ~w(
    academic-programs:select
    week-schedule-grid:close_edit_course
    switch_mode
  )

  @denied_flash "You have view-only access to scheduling."

  def on_mount(:default, _params, _session, socket) do
    editor? = Access.can_edit?(socket.assigns.current_user, :scheduling)

    socket = assign(socket, :scheduling_editor?, editor?)

    if editor? do
      {:cont, socket}
    else
      {:cont, attach_hook(socket, :scheduling_view_only, :handle_event, &gate/3)}
    end
  end

  @doc """
  Whether a viewer may send `event`: `:view` yes, `:edit` no, `:unknown` means
  nobody has classified it and it is refused.
  """
  def classify(event) when is_binary(event) do
    cond do
      event in @view_events -> :view
      namespace(event) in @view_namespaces -> :view
      namespace(event) in @editor_namespaces -> :edit
      true -> :unknown
    end
  end

  def view_namespaces, do: @view_namespaces

  def editor_namespaces, do: @editor_namespaces

  defp gate(event, _params, socket) do
    case classify(event) do
      :view ->
        {:cont, socket}

      :edit ->
        Logger.info(
          "Refused scheduling edit for view-only user event=#{event} user=#{user_email(socket)}"
        )

        {:halt, put_flash(socket, :error, @denied_flash)}

      :unknown ->
        Logger.warning(
          "Refused unclassified scheduling event event=#{event} user=#{user_email(socket)} — " <>
            "add it to SchedulingAccess before viewers can use it"
        )

        {:halt, put_flash(socket, :error, @denied_flash)}
    end
  end

  defp namespace(event) do
    case String.split(event, ":", parts: 2) do
      [namespace, _rest] -> namespace
      _no_namespace -> nil
    end
  end

  defp user_email(%{assigns: %{current_user: %{email: email}}}), do: email
  defp user_email(_socket), do: "unknown"
end
