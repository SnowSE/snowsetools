defmodule SnowSeTools.Snow.SnowCourseCachePubSub do
  @topic "snow_course_cache"

  def subscribe do
    Phoenix.PubSub.subscribe(SnowSeTools.PubSub, @topic)
  end

  def broadcast_course_cache_updated(term_code) when is_binary(term_code) do
    Phoenix.PubSub.broadcast(
      SnowSeTools.PubSub,
      @topic,
      {:snow_course_cache, {:course_cache_updated, term_code}}
    )
  end

  def broadcast_roster_cache_updated(term_code) when is_binary(term_code) do
    Phoenix.PubSub.broadcast(
      SnowSeTools.PubSub,
      @topic,
      {:snow_course_cache, {:roster_cache_updated, term_code}}
    )
  end

  def broadcast_course_cache_deleted(term_code) when is_binary(term_code) do
    Phoenix.PubSub.broadcast(
      SnowSeTools.PubSub,
      @topic,
      {:snow_course_cache, {:course_cache_deleted, term_code}}
    )
  end
end
