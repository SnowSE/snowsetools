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

  def broadcast_schedule_owner_metadata_upserted(term_code, schedule_owner)
      when is_binary(term_code) do
    Phoenix.PubSub.broadcast(
      SnowSeTools.PubSub,
      @topic,
      {:schedule_owners,
       {:schedule_owner_metadata_upserted,
        %{term_code: term_code, schedule_owner: schedule_owner}}}
    )
  end

  def broadcast_schedule_owner_metadata_deleted(term_code, owner_key)
      when is_binary(term_code) and is_binary(owner_key) do
    Phoenix.PubSub.broadcast(
      SnowSeTools.PubSub,
      @topic,
      {:schedule_owners,
       {:schedule_owner_metadata_deleted, %{term_code: term_code, owner_key: owner_key}}}
    )
  end

  def broadcast_schedule_owner_detail_changed(term_code, owner_key, detail)
      when is_binary(term_code) and is_binary(owner_key) do
    Phoenix.PubSub.broadcast(
      SnowSeTools.PubSub,
      @topic,
      {:schedule_owners,
       {:schedule_owner_detail_changed,
        %{term_code: term_code, owner_key: owner_key, detail: detail}}}
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
