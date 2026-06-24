defmodule SnowSeTools.Scheduling.ScheduleOwnerPubSub do
  @topic "schedule_owners"

  def subscribe do
    Phoenix.PubSub.subscribe(SnowSeTools.PubSub, @topic)
  end

  def broadcast_terms_changed(terms) when is_list(terms) do
    Phoenix.PubSub.broadcast(
      SnowSeTools.PubSub,
      @topic,
      {:schedule_owners, {:terms_changed, terms}}
    )
  end

  def broadcast_term_schedule_owners_replaced(term_code, schedule_owners)
      when is_binary(term_code) and is_list(schedule_owners) do
    Phoenix.PubSub.broadcast(
      SnowSeTools.PubSub,
      @topic,
      {:schedule_owners,
       {:term_schedule_owners_replaced, %{term_code: term_code, schedule_owners: schedule_owners}}}
    )
  end

  def broadcast_term_deleted(term_code) when is_binary(term_code) do
    Phoenix.PubSub.broadcast(
      SnowSeTools.PubSub,
      @topic,
      {:schedule_owners, {:term_deleted, %{term_code: term_code}}}
    )
  end
end
