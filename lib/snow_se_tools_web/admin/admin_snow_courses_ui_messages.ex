defmodule SnowSeToolsWeb.Admin.AdminSnowCoursesUIMessages do
  def send_snow_cache_terms(pid: pid, terms: terms) when is_pid(pid) do
    send(pid, {:admin_ui_snow_cache_terms, terms})
  end

  def send_snow_cache_snapshot_error(pid: pid, reason: reason) when is_pid(pid) do
    send(pid, {:admin_ui_snow_cache_snapshot_error, reason})
  end

  def send_snow_cache_action_result(pid: pid, result: result) when is_pid(pid) do
    send(pid, {:admin_ui_snow_cache_action_result, result})
  end

  defmacro __using__(_opts) do
    quote do
      def handle_info({:admin_ui_snow_cache_terms, terms}, socket) do
        send_update(SnowSeToolsWeb.Admin.SnowCacheComponent,
          id: "snow-cache-component",
          terms: terms,
          snapshot_error: nil
        )

        {:noreply, socket}
      end

      def handle_info({:admin_ui_snow_cache_snapshot_error, reason}, socket) do
        send_update(SnowSeToolsWeb.Admin.SnowCacheComponent,
          id: "snow-cache-component",
          snapshot_error: snow_format_error(reason)
        )

        {:noreply, socket}
      end

      def handle_info({:admin_ui_snow_cache_action_result, {:ok, message}}, socket) do
        send_update(SnowSeToolsWeb.Admin.SnowCacheComponent,
          id: "snow-cache-component",
          sync_result: {:ok, message}
        )

        {:noreply, socket}
      end

      def handle_info({:admin_ui_snow_cache_action_result, {:error, reason}}, socket) do
        send_update(SnowSeToolsWeb.Admin.SnowCacheComponent,
          id: "snow-cache-component",
          sync_result: {:error, snow_format_error(reason)}
        )

        {:noreply, socket}
      end

      defp snow_format_error(reason) when is_binary(reason), do: reason
      defp snow_format_error(reason), do: inspect(reason)
    end
  end
end
