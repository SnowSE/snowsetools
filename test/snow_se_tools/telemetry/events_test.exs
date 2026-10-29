defmodule SnowSeTools.Telemetry.EventsTest do
  use ExUnit.Case, async: false

  require OpenTelemetry.Tracer
  alias SnowSeTools.Telemetry.Events

  setup do
    original = Application.get_env(:snow_se_tools, :otel)
    Application.put_env(:snow_se_tools, :otel, endpoint: "http://127.0.0.1:1")

    on_exit(fn ->
      :sys.replace_state(Events, &%{&1 | buffer: [], count: 0})
      Application.put_env(:snow_se_tools, :otel, original)
    end)
  end

  test "an event recorded inside a span carries that span's trace and span ids" do
    {trace_id, span_id} =
      OpenTelemetry.Tracer.with_span "events-test" do
        span_ctx = OpenTelemetry.Tracer.current_span_ctx()
        Events.record("test.trace_context.recorded")
        {OpenTelemetry.Span.hex_trace_id(span_ctx), OpenTelemetry.Span.hex_span_id(span_ctx)}
      end

    assert %{traceId: ^trace_id, spanId: ^span_id} = recorded("test.trace_context.recorded")
    assert byte_size(trace_id) == 32
    assert byte_size(span_id) == 16
  end

  test "an event recorded outside any span has no trace ids" do
    Events.record("test.trace_context.untraced")

    record = recorded("test.trace_context.untraced")
    refute Map.has_key?(record, :traceId)
    refute Map.has_key?(record, :spanId)
  end

  defp recorded(event) do
    Events
    |> :sys.get_state()
    |> Map.fetch!(:buffer)
    |> Enum.find(&(&1.body == %{stringValue: event}))
  end
end
