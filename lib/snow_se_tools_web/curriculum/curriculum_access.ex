defmodule SnowSeToolsWeb.Curriculum.CurriculumAccess do
  @moduledoc """
  Keeps viewers of the curriculum map from sending anything that changes it.

  Every event that writes is named `curriculum-edit:…`. Viewers may send the
  events listed in `@view_events`, which only move their own window onto the
  map; an event that is in neither group is refused and logged, so one added
  later is blocked until someone decides it is safe.
  """

  import Phoenix.Component, only: [assign: 3]
  import Phoenix.LiveView, only: [attach_hook: 4, put_flash: 3]

  require Logger

  alias SnowSeTools.Data.Access

  @edit_prefix "curriculum-edit:"

  @view_events ~w(
    select_program
    set_overlay
    filter_threads
    filter_skills
  )

  @denied_flash "You have view-only access to the curriculum map."

  def edit_prefix, do: @edit_prefix

  def on_mount(:default, _params, _session, socket) do
    editor? = Access.can_edit?(socket.assigns.current_user, :curriculum)
    socket = assign(socket, :curriculum_editor?, editor?)

    if editor? do
      {:cont, socket}
    else
      {:cont, attach_hook(socket, :curriculum_view_only, :handle_event, &gate/3)}
    end
  end

  def classify(event) when is_binary(event) do
    cond do
      String.starts_with?(event, @edit_prefix) -> :edit
      event in @view_events -> :view
      true -> :unknown
    end
  end

  defp gate(event, _params, socket) do
    case classify(event) do
      :view ->
        {:cont, socket}

      :edit ->
        Logger.info(
          "Refused curriculum edit for view-only user event=#{event} user=#{user_email(socket)}"
        )

        {:halt, put_flash(socket, :error, @denied_flash)}

      :unknown ->
        Logger.warning(
          "Refused unclassified curriculum event event=#{event} user=#{user_email(socket)} — " <>
            "add it to CurriculumAccess before viewers can use it"
        )

        {:halt, put_flash(socket, :error, @denied_flash)}
    end
  end

  defp user_email(%{assigns: %{current_user: %{email: email}}}), do: email
  defp user_email(_socket), do: "unknown"
end
