defmodule SnowSeTools.Curriculum.CurriculumPubSub do
  @topic "curriculum"

  def subscribe do
    Phoenix.PubSub.subscribe(SnowSeTools.PubSub, @topic)
  end

  @doc "Something in the map changed; viewers reload it."
  def broadcast_changed do
    Phoenix.PubSub.broadcast(SnowSeTools.PubSub, @topic, {:curriculum, :changed})
  end

  def broadcast_run(status) do
    Phoenix.PubSub.broadcast(SnowSeTools.PubSub, @topic, {:curriculum, {:run, status}})
  end
end
