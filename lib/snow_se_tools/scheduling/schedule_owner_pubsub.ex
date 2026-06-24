defmodule SnowSeTools.Scheduling.ScheduleOwnerPubSub do
  @topic "schedule_owners"

  def subscribe do
    Phoenix.PubSub.subscribe(SnowSeTools.PubSub, @topic)
  end

  def broadcast_schedule_owners_changed(term_code) do
    Phoenix.PubSub.broadcast(
      SnowSeTools.PubSub,
      @topic,
      {:schedule_owners_changed, term_code}
    )
  end
end
