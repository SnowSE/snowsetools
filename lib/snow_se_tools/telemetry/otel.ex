defmodule SnowSeTools.Telemetry.Otel do
  @moduledoc """
  Turns on OpenTelemetry tracing for Phoenix, Bandit and Ecto.

  Tracing answers "why was this slow" and "where did this break"; the events in
  `SnowSeTools.Telemetry.Events` answer "who used what". The collector keeps
  every errored and every slow trace and samples the rest, so this stays cheap.

  Silently does nothing when `OTEL_EXPORTER_OTLP_ENDPOINT` is unset, which is
  the normal state in dev and test.
  """

  require Logger

  def setup do
    if SnowSeTools.Telemetry.Events.enabled?() do
      OpentelemetryBandit.setup()
      OpentelemetryPhoenix.setup(adapter: :bandit)
      OpentelemetryEcto.setup([:snow_se_tools, :repo])
      SnowSeTools.Telemetry.LogForwarder.attach()

      Logger.info(
        "OpenTelemetry tracing enabled endpoint=#{Application.get_env(:snow_se_tools, :otel)[:endpoint]}"
      )
    end

    :ok
  end
end
