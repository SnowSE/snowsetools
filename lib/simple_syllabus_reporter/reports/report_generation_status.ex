defmodule SimpleSyllabusReporter.Reports.ReportGenerationStatus do
  alias SimpleSyllabusReporter.Reports.ReportGenerator

  defmodule ItemResult do
    @enforce_keys [:code, :element_id, :result]
    defstruct [:code, :element_id, :result]
  end

  defmodule PendingUpdate do
    @enforce_keys [:code, :element_ids]
    defstruct [:code, :element_ids]
  end

  @pubsub SimpleSyllabusReporter.PubSub

  def subscribe(code) do
    Phoenix.PubSub.subscribe(@pubsub, ReportGenerator.report_topic(code))
    Phoenix.PubSub.subscribe(@pubsub, ReportGenerator.pending_topic(code))
  end

  def unsubscribe(code) do
    Phoenix.PubSub.unsubscribe(@pubsub, ReportGenerator.report_topic(code))
    Phoenix.PubSub.unsubscribe(@pubsub, ReportGenerator.pending_topic(code))
  end

  def request_pending(codes) when is_list(codes) do
    ReportGenerator.request_pending(codes)
  end

  def publish_item_result(code, element_id, result) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      ReportGenerator.report_topic(code),
      %ItemResult{code: code, element_id: element_id, result: result}
    )
  end

  def publish_pending_update(code, element_ids) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      ReportGenerator.pending_topic(code),
      %PendingUpdate{code: code, element_ids: element_ids}
    )
  end
end
