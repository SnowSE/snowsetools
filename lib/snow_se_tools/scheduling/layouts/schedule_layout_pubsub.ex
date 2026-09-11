defmodule SnowSeTools.Scheduling.ScheduleLayoutPubSub do
  @moduledoc """
  Broadcasts changes to server-backed layouts so every open scheduling page
  keeps an accurate Load Layout list — shared layouts especially, since one
  person saving one is immediately loadable by everyone else.
  """

  @topic "schedule_layouts"

  def subscribe do
    Phoenix.PubSub.subscribe(SnowSeTools.PubSub, @topic)
  end

  def broadcast_layout_saved(layout) when is_map(layout) do
    broadcast({:layout_saved, layout})
  end

  def broadcast_layout_deleted(layout_id) when is_binary(layout_id) do
    broadcast({:layout_deleted, %{id: layout_id}})
  end

  defp broadcast(event) do
    Phoenix.PubSub.broadcast(SnowSeTools.PubSub, @topic, {:schedule_layouts, event})
  end
end
