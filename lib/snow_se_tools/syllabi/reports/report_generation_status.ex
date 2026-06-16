defmodule SnowSeTools.Reports.ReportGenerationStatus do
  alias SnowSeTools.Reports.ReportGeneratorDomainManger

  defmodule ItemResult do
    @enforce_keys [:code, :element_id, :result]
    defstruct [:code, :element_id, :result]
  end

  defmodule PendingUpdate do
    @enforce_keys [:pending]
    defstruct [:pending]
  end

  @pubsub SnowSeTools.PubSub
  @topic "report_generator:updates"

  def subscribe do
    Phoenix.PubSub.subscribe(@pubsub, @topic)
  end

  def unsubscribe do
    Phoenix.PubSub.unsubscribe(@pubsub, @topic)
  end

  def request_pending(codes) when is_list(codes) do
    ReportGeneratorDomainManger.request_pending(codes)
  end

  def publish_item_result(code, element_id, result) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, %ItemResult{
      code: code,
      element_id: element_id,
      result: result
    })
  end

  def publish_pending_update(pending) do
    Phoenix.PubSub.broadcast(@pubsub, @topic, %PendingUpdate{pending: pending})
  end
end
