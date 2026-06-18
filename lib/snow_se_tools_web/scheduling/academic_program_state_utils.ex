defmodule SnowSeToolsWeb.Scheduling.AcademicProgramStateUtils do
  @moduledoc false

  require Logger

  import Phoenix.Component, only: [assign: 2, assign: 3]

  alias Phoenix.LiveView
  alias SnowSeToolsWeb.Scheduling.ScheduleOwnerData

  def handle_message({:loaded, {:ok, programs}}, socket) do
    {:noreply, assign_programs(socket: socket, programs: programs)}
  end

  def handle_message({:loaded, {:error, reason}}, socket) do
    Logger.error("SchedulingLive failed to load academic programs reason=#{inspect(reason)}")
    {:noreply, LiveView.put_flash(socket, :error, "Could not load academic programs.")}
  end

  def handle_message({:action_result, {:ok, message, program}}, socket) do
    socket =
      assign(socket, :selected_program_id, program && program["id"])

    {:noreply, LiveView.put_flash(socket, :info, message)}
  end

  def handle_message({:action_result, {:error, reason}}, socket) do
    {:noreply, LiveView.put_flash(socket, :error, "Academic program error: #{inspect(reason)}")}
  end

  def handle_message(diff, socket)
      when elem(diff, 0) in [:program_created, :program_updated, :program_deleted] do
    programs = apply_program_diff(programs: socket.assigns.academic_programs, diff: diff)
    {:noreply, assign_programs(socket: socket, programs: programs)}
  end

  defp assign_programs(socket: socket, programs: programs) do
    selected_schedule_owner_keys =
      selected_keys_available_after_program_update(socket: socket, programs: programs)

    assign(socket,
      academic_programs: programs,
      selected_schedule_owner_keys: selected_schedule_owner_keys
    )
  end

  defp selected_keys_available_after_program_update(socket: socket, programs: programs) do
    selected_keys = MapSet.new(socket.assigns.selected_schedule_owner_keys)

    available_keys =
      ScheduleOwnerData.build_schedule_owners(
        courses: socket.assigns.courses,
        query: socket.assigns.query,
        academic_programs: programs
      )
      |> MapSet.new(& &1.key)

    selected_keys
    |> MapSet.intersection(available_keys)
    |> MapSet.to_list()
  end

  defp apply_program_diff(programs: programs, diff: {:program_created, program}) do
    programs
    |> Enum.reject(&(&1["id"] == program["id"]))
    |> Kernel.++([program])
    |> sort_programs()
  end

  defp apply_program_diff(programs: programs, diff: {:program_updated, program}) do
    programs
    |> Enum.map(fn existing ->
      if existing["id"] == program["id"], do: program, else: existing
    end)
    |> sort_programs()
  end

  defp apply_program_diff(programs: programs, diff: {:program_deleted, program_id}) do
    Enum.reject(programs, &(&1["id"] == program_id))
  end

  defp sort_programs(programs), do: Enum.sort_by(programs, &String.downcase(&1["name"] || ""))
end
