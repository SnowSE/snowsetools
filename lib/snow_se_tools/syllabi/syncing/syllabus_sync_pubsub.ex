defmodule SnowSeTools.Syllabi.Syncing.SyllabusSyncPubsub do
  require Logger

  @topic "syllabus:sync_complete"

  def broadcast_sync_complete(sync_id) do
    Phoenix.PubSub.broadcast(
      SnowSeTools.PubSub,
      @topic,
      {:simple_syllabus_sync, {:sync_complete, sync_id}}
    )
  end

  def broadcast_sync_error(source, error_message) do
    Logger.error("API error from #{source}: #{error_message}")

    Phoenix.PubSub.broadcast(
      SnowSeTools.PubSub,
      @topic,
      {:simple_syllabus_sync, {:sync_error, source, error_message}}
    )
  end

  def broadcast_sync_progress(%{total: total, completed: completed}) do
    Phoenix.PubSub.broadcast(
      SnowSeTools.PubSub,
      @topic,
      {:simple_syllabus_sync, {:sync_progress, %{total: total, completed: completed}}}
    )
  end

  def subscribe_to_sync_events do
    Phoenix.PubSub.subscribe(SnowSeTools.PubSub, @topic)
  end
end
