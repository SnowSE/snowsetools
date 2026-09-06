defmodule SnowSeTools.Telemetry.LogForwarder do
  @moduledoc """
  Forwards WARN and ERROR log lines to the collector so the Problems dashboard
  sees them.

  `SnowSeTools.Telemetry.Events` only carries deliberate app events. Without
  this, a warning would be visible in `docker logs` and nowhere else, which is
  the opposite of the point -- the .NET and Node sites forward theirs through
  their SDKs, and this keeps Phoenix consistent with them.

  Attached as an Erlang `:logger` handler rather than a Phoenix backend so it
  also catches warnings raised by libraries. INFO and DEBUG are deliberately
  not forwarded: the collector would drop them anyway.
  """

  alias SnowSeTools.Telemetry.Events

  @handler_id :snowse_otel_log_forwarder

  def attach do
    if Events.enabled?() and not attached?() do
      :logger.add_handler(@handler_id, __MODULE__, %{level: :warning})
    end

    :ok
  end

  defp attached? do
    Enum.any?(:logger.get_handler_ids(), &(&1 == @handler_id))
  end

  @doc false
  def log(%{level: level, msg: msg, meta: meta}, _config) do
    # Events logs its own export failures. Forwarding those would put a new
    # record in the buffer every time a flush fails, which is the one way this
    # could feed itself.
    unless meta[:otel_skip] do
      Events.record_log(level, message(msg), meta)
    end

    :ok
  end

  defp message({:string, chardata}), do: to_string_safe(chardata)
  defp message({:report, report}), do: inspect(report)

  defp message({format, args}) when is_list(args) do
    format |> :io_lib.format(args) |> to_string_safe()
  rescue
    _ -> inspect({format, args})
  end

  defp message(other), do: inspect(other)

  defp to_string_safe(chardata) do
    IO.chardata_to_string(chardata)
  rescue
    _ -> inspect(chardata)
  end
end
