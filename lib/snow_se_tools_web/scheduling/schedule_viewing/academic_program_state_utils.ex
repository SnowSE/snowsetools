defmodule SnowSeToolsWeb.Scheduling.AcademicProgramStateUtils do
  require Logger

  import Phoenix.Component, only: [assign: 3]

  alias Phoenix.LiveView
  alias SnowSeToolsWeb.Scheduling.ScheduleOwnerData

  def handle_message({:loaded, {:ok, programs}}, socket) do
    {:noreply, assign(socket, :academic_programs, programs)}
  end

  def handle_message({:loaded, {:error, reason}}, socket) do
    Logger.error("SchedulingLive failed to load academic programs reason=#{inspect(reason)}")
    {:noreply, LiveView.put_flash(socket, :error, "Could not load academic programs.")}
  end

  def handle_message({:action_result, {:ok, _message, program}}, socket) do
    {:noreply, assign(socket, :selected_program_id, program && program["id"])}
  end

  def handle_message({:action_result, {:error, reason}}, socket) do
    {:noreply, LiveView.put_flash(socket, :error, "Academic program error: #{inspect(reason)}")}
  end

  def handle_message(diff, socket)
      when elem(diff, 0) in [:program_created, :program_updated, :program_deleted] do
    programs = apply_program_diff(programs: socket.assigns.academic_programs, diff: diff)
    {:noreply, assign(socket, :academic_programs, programs)}
  end

  def filter_selected_keys(selected_schedule_owner_keys, courses, query, programs) do
    selected_keys = MapSet.new(selected_schedule_owner_keys)

    available_keys =
      ScheduleOwnerData.build_schedule_owners(
        courses: courses,
        query: query,
        academic_programs: programs
      )
      |> MapSet.new(& &1.key)

    MapSet.intersection(selected_keys, available_keys)
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
