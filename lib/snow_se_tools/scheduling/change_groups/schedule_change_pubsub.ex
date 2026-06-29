defmodule SnowSeTools.Scheduling.ScheduleChangePubSub do
  @topic "schedule_changes"

  def subscribe do
    Phoenix.PubSub.subscribe(SnowSeTools.PubSub, @topic)
  end

  def broadcast_group_created(group) do
    Phoenix.PubSub.broadcast(
      SnowSeTools.PubSub,
      @topic,
      {:schedule_changes, {:group_created, group}}
    )
  end

  def broadcast_group_deleted(group_id) do
    Phoenix.PubSub.broadcast(
      SnowSeTools.PubSub,
      @topic,
      {:schedule_changes, {:group_deleted, group_id}}
    )
  end

  def broadcast_group_updated(group) do
    Phoenix.PubSub.broadcast(
      SnowSeTools.PubSub,
      @topic,
      {:schedule_changes, {:group_updated, group}}
    )
  end

  def broadcast_change_updated(group_id, change) do
    Phoenix.PubSub.broadcast(
      SnowSeTools.PubSub,
      @topic,
      {:schedule_changes, {:change_updated, group_id, change}}
    )
  end

  def broadcast_change_removed(group_id, change_id) do
    Phoenix.PubSub.broadcast(
      SnowSeTools.PubSub,
      @topic,
      {:schedule_changes, {:change_removed, group_id, change_id}}
    )
  end

  def broadcast_conflict_check_updated(group_id) do
    Phoenix.PubSub.broadcast(
      SnowSeTools.PubSub,
      @topic,
      {:schedule_changes, {:conflict_check_updated, group_id}}
    )
  end
end
