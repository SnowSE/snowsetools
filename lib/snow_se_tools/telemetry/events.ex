defmodule SnowSeTools.Telemetry.Events do
  @moduledoc """
  Records app events -- the signal behind the "Who's using what" dashboard on
  otel.snowse.io.

  An app event is a deliberate statement that a person used a feature:

      Events.record("syllabus.report.generated", user: user, attributes: %{term: term})

  The collector keeps every record carrying an `app.event` attribute for 30
  days and throws away ordinary log chatter, so calling this is what makes an
  action show up in the dashboards. The first segment of the name becomes the
  feature bucket the dashboard groups by, so name events
  `<feature>.<thing>.<verb>` and keep the leading segment stable.

  ## Why this is hand-rolled

  Traces go through the OpenTelemetry SDK, but the stable Erlang SDK has no
  logs support -- OTLP logs live only in `:opentelemetry_experimental`. Rather
  than put the main signal on an unstable dependency, events are batched here
  and POSTed to the collector as OTLP/HTTP JSON with `Req`, which the project
  already depends on.

  Recording is a cast and never blocks or raises in the caller: telemetry must
  not be able to take a page down. When `OTEL_EXPORTER_OTLP_ENDPOINT` is unset
  (dev, test, CI) `record/2` is a no-op.
  """

  use GenServer
  require Logger

  @flush_interval_ms 5_000
  # A hard ceiling, not a flush trigger. A crash loop can produce thousands of
  # identical errors a second; without this the exporter would faithfully
  # forward every one and the disk budget would go with it. Beyond the cap
  # records are dropped and counted, and the count is reported on the next
  # flush so the loss is visible rather than silent.
  @max_buffer 500
  @severity %{ok: {9, "INFO"}, error: {17, "ERROR"}}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @doc """
  Records that something happened.

  Options:

    * `:user` — a `%User{}`, an e-mail string, or nil
    * `:outcome` — `:ok` (default) or `:error`
    * `:attributes` — extra context, e.g. `%{term: "202430", count: 12}`
  """
  @spec record(String.t(), keyword()) :: :ok
  def record(event, opts \\ []) when is_binary(event) do
    if enabled?() do
      GenServer.cast(__MODULE__, {:record, build(event, opts)})
    end

    :ok
  catch
    kind, reason ->
      Logger.warning("Telemetry.Events.record failed event=#{event} #{inspect({kind, reason})}",
        otel_skip: true
      )

      :ok
  end

  def enabled?, do: Application.get_env(:snow_se_tools, :otel)[:endpoint] != nil

  @doc """
  Records a WARN/ERROR log line. Called by `SnowSeTools.Telemetry.LogForwarder`,
  not directly -- use `record/2` for anything you want counted as usage.

  These carry no `app.event`, so the collector keeps them on severity alone and
  they never show up as feature usage.
  """
  @spec record_log(atom(), String.t(), map()) :: :ok
  def record_log(level, message, meta \\ %{}) do
    if enabled?() do
      GenServer.cast(__MODULE__, {:record, build_log(level, message, meta)})
    end

    :ok
  catch
    _kind, _reason -> :ok
  end

  @impl true
  def init(_opts) do
    Process.flag(:trap_exit, true)
    schedule_flush()
    {:ok, %{buffer: [], count: 0, dropped: 0, resource: resource_attributes()}}
  end

  @impl true
  def handle_cast({:record, _record}, %{count: count} = state) when count >= @max_buffer do
    {:noreply, %{state | dropped: state.dropped + 1}}
  end

  def handle_cast({:record, record}, state) do
    {:noreply, %{state | buffer: [record | state.buffer], count: state.count + 1}}
  end

  @impl true
  def handle_info(:flush, state) do
    schedule_flush()
    {:noreply, flush(state)}
  end

  @impl true
  def terminate(_reason, state) do
    flush(state)
    :ok
  end

  defp schedule_flush, do: Process.send_after(self(), :flush, @flush_interval_ms)

  defp flush(%{buffer: []} = state), do: %{state | count: 0, dropped: 0}

  defp flush(%{buffer: buffer, dropped: dropped, resource: resource} = state) do
    records = Enum.reverse(buffer) ++ drop_notice(dropped)

    payload = %{
      resourceLogs: [
        %{
          resource: %{attributes: resource},
          scopeLogs: [
            %{
              scope: %{name: "snow_se_tools"},
              logRecords: records
            }
          ]
        }
      ]
    }

    endpoint = Application.get_env(:snow_se_tools, :otel)[:endpoint]

    case Req.post(endpoint <> "/v1/logs", json: payload, receive_timeout: 5_000, retry: false) do
      {:ok, %{status: status}} when status in 200..299 ->
        :ok

      {:ok, %{status: status, body: body}} ->
        Logger.warning("Telemetry export rejected status=#{status} body=#{inspect(body)}",
          otel_skip: true
        )

      {:error, reason} ->
        Logger.warning("Telemetry export failed reason=#{inspect(reason)}", otel_skip: true)
    end

    %{state | buffer: [], count: 0, dropped: 0}
  end

  defp drop_notice(0), do: []

  defp drop_notice(dropped) do
    [build_log(:warning, "telemetry buffer full, dropped #{dropped} record(s)", %{})]
  end

  @log_severity %{
    emergency: {21, "FATAL"},
    alert: {19, "FATAL"},
    critical: {19, "FATAL"},
    error: {17, "ERROR"},
    warning: {13, "WARN"},
    warn: {13, "WARN"}
  }

  defp build_log(level, message, meta) do
    {severity_number, severity_text} = Map.get(@log_severity, level, {13, "WARN"})

    attributes =
      %{}
      |> put_if("code.module", meta[:module])
      |> put_if("code.function", meta[:function])
      |> put_if("code.lineno", meta[:line])
      |> Enum.map(&attribute/1)

    %{
      timeUnixNano: to_string(System.system_time(:nanosecond)),
      severityNumber: severity_number,
      severityText: severity_text,
      body: %{stringValue: String.slice(message, 0, 4096)},
      attributes: attributes
    }
    |> Map.merge(trace_context())
  end

  defp put_if(map, _key, nil), do: map

  defp put_if(map, key, value) when is_binary(value) or is_integer(value),
    do: Map.put(map, key, value)

  defp put_if(map, key, value), do: Map.put(map, key, inspect(value))

  defp build(event, opts) do
    outcome = Keyword.get(opts, :outcome, :ok)
    {severity_number, severity_text} = Map.fetch!(@severity, outcome)

    attributes =
      opts
      |> Keyword.get(:attributes, %{})
      |> Map.new(fn {k, v} -> {to_string(k), v} end)
      |> Map.put("app.event", event)
      |> Map.put("app.outcome", to_string(outcome))
      |> put_user(Keyword.get(opts, :user))
      |> Enum.map(&attribute/1)

    %{
      timeUnixNano: to_string(System.system_time(:nanosecond)),
      severityNumber: severity_number,
      severityText: severity_text,
      body: %{stringValue: event},
      attributes: attributes
    }
    |> Map.merge(trace_context())
  end

  defp put_user(attributes, nil), do: attributes

  defp put_user(attributes, email) when is_binary(email),
    do: Map.put(attributes, "user.email", email)

  defp put_user(attributes, %{email: email}) when is_binary(email),
    do: Map.put(attributes, "user.email", email)

  defp put_user(attributes, %{"email" => email}) when is_binary(email),
    do: Map.put(attributes, "user.email", email)

  defp put_user(attributes, _), do: attributes

  defp attribute({key, value}) when is_boolean(value), do: %{key: key, value: %{boolValue: value}}

  defp attribute({key, value}) when is_integer(value),
    do: %{key: key, value: %{intValue: to_string(value)}}

  defp attribute({key, value}) when is_float(value), do: %{key: key, value: %{doubleValue: value}}

  defp attribute({key, value}) when is_binary(value),
    do: %{key: key, value: %{stringValue: value}}

  defp attribute({key, value}), do: %{key: key, value: %{stringValue: inspect(value)}}

  # Stamping the current span onto the event is what lets Grafana jump from a
  # line on the usage dashboard to the trace for that exact request.
  defp trace_context do
    case :otel_tracer.current_span_ctx() do
      {:span_ctx, trace_id, span_id, _, _, _, _, _, _} when is_integer(trace_id) ->
        %{traceId: hex(trace_id, 32), spanId: hex(span_id, 16)}

      _ ->
        %{}
    end
  rescue
    _ -> %{}
  end

  defp hex(id, width) do
    id
    |> Integer.to_string(16)
    |> String.downcase()
    |> String.pad_leading(width, "0")
  end

  defp resource_attributes do
    otel = Application.get_env(:snow_se_tools, :otel, [])

    [
      {"service.name", Keyword.get(otel, :service_name, "snowse-tools")},
      {"service.namespace", "snowse"},
      {"deployment.environment", Keyword.get(otel, :environment, "unknown")}
    ]
    |> Enum.map(&attribute/1)
  end
end
