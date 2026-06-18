defmodule SnowSeTools.AcademicPrograms.AcademicProgramPubSub do
  @topic "academic_programs"

  def subscribe do
    Phoenix.PubSub.subscribe(SnowSeTools.PubSub, @topic)
  end

  def broadcast_program_created(program) do
    Phoenix.PubSub.broadcast(
      SnowSeTools.PubSub,
      @topic,
      {:academic_programs, {:program_created, program}}
    )
  end

  def broadcast_program_updated(program) do
    Phoenix.PubSub.broadcast(
      SnowSeTools.PubSub,
      @topic,
      {:academic_programs, {:program_updated, program}}
    )
  end

  def broadcast_program_deleted(program_id) do
    Phoenix.PubSub.broadcast(
      SnowSeTools.PubSub,
      @topic,
      {:academic_programs, {:program_deleted, program_id}}
    )
  end
end
