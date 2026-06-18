defmodule SnowSeTools.AcademicPrograms.ProgramDomainManager do
  use GenServer
  require Logger

  alias SnowSeTools.AcademicPrograms.{AcademicProgramPubSub, ProgramDb}

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def request_programs(pid: pid) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:request_programs, pid})
  end

  def create_program(pid: pid, attrs: attrs) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:create_program, pid, attrs})
  end

  def update_program(pid: pid, id: id, attrs: attrs) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:update_program, pid, id, attrs})
  end

  def delete_program(pid: pid, id: id) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:delete_program, pid, id})
  end

  def init(:ok) do
    case ProgramDb.bootstrap_tables() do
      :ok ->
        {:ok, %{}}

      {:error, reason} ->
        Logger.error("Academic program bootstrap failed reason=#{inspect(reason)}")
        {:stop, reason}
    end
  end

  def handle_cast({:request_programs, pid}, state) do
    send_programs(pid)
    {:noreply, state}
  end

  def handle_cast({:create_program, pid, attrs}, state) do
    result = ProgramDb.create_program(attrs: attrs)
    send(pid, {:academic_programs, {:action_result, result_message(result, "created")}})

    case result do
      {:ok, program} -> AcademicProgramPubSub.broadcast_program_created(program)
      {:error, _reason} -> :ok
    end

    {:noreply, state}
  end

  def handle_cast({:update_program, pid, id, attrs}, state) do
    result = ProgramDb.update_program(id: id, attrs: attrs)
    send(pid, {:academic_programs, {:action_result, result_message(result, "updated")}})

    case result do
      {:ok, program} -> AcademicProgramPubSub.broadcast_program_updated(program)
      {:error, _reason} -> :ok
    end

    {:noreply, state}
  end

  def handle_cast({:delete_program, pid, id}, state) do
    result = ProgramDb.delete_program(id: id)
    send(pid, {:academic_programs, {:action_result, delete_message(result)}})

    case result do
      :ok -> AcademicProgramPubSub.broadcast_program_deleted(id)
      {:error, _reason} -> :ok
    end

    {:noreply, state}
  end

  defp send_programs(pid) do
    send(pid, {:academic_programs, {:loaded, ProgramDb.list_programs()}})
  end

  defp result_message({:ok, program}, action), do: {:ok, "#{program["name"]} #{action}.", program}
  defp result_message({:error, reason}, _action), do: {:error, reason}

  defp delete_message(:ok), do: {:ok, "Academic program deleted.", nil}
  defp delete_message({:error, reason}), do: {:error, reason}
end
