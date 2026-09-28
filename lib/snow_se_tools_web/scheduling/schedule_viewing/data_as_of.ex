defmodule SnowSeToolsWeb.Scheduling.DataAsOf do
  use SnowSeToolsWeb, :html

  attr :term, :map, default: nil, doc: "The selected term, as listed by the owner domain manager."

  @doc """
  When the selected term's schedule was last pulled from Snow. The server
  renders UTC; the hook rewrites it in the viewer's own time zone.
  """
  def data_as_of(assigns) do
    assigns = assign(assigns, :cached_at, parse_cached_at(assigns.term))

    ~H"""
    <p :if={@cached_at} id="scheduling-data-as-of" class="text-xs text-slate-500">
      Data as of
      <time
        id="scheduling-data-as-of-time"
        datetime={DateTime.to_iso8601(@cached_at)}
        phx-hook=".LocalDateTime"
      >
        {Calendar.strftime(@cached_at, "%b %-d, %Y %H:%M UTC")}
      </time>
    </p>
    <script :type={Phoenix.LiveView.ColocatedHook} name=".LocalDateTime">
      export default {
        mounted() { this.format(); },
        updated() { this.format(); },
        format() {
          const date = new Date(this.el.getAttribute("datetime"));
          if (isNaN(date)) return;
          this.el.textContent = date.toLocaleString(undefined, {
            dateStyle: "medium",
            timeStyle: "short"
          });
        }
      }
    </script>
    """
  end

  defp parse_cached_at(%{"cached_at" => cached_at}) when is_binary(cached_at) do
    case DateTime.from_iso8601(cached_at) do
      {:ok, datetime, _offset} -> datetime
      _ -> nil
    end
  end

  defp parse_cached_at(_term), do: nil
end
