defmodule SimpleSyllabusReporterWeb.AI.CompletionDetails do
  use SimpleSyllabusReporterWeb, :html

  def completion_details(assigns) do
    ~H"""
    <div class="border-t border-slate-700 ">
      <%= for msg <- messages(@completion["messages"]) do %>
        <div class="px-2 py-3">
          <span class={[
            "text-[10px] font-bold uppercase tracking-wider",
            case msg["role"] do
              "system" -> "text-purple-400"
              "user" -> "text-blue-400"
              "assistant" -> "text-green-400"
              _ -> "text-slate-400"
            end
          ]}>
            {msg["role"]}
          </span>
          <pre class="ps-2 text-xs text-slate-300 whitespace-pre-wrap break-words font-mono leading-relaxed">{msg["content"]}</pre>
        </div>
      <% end %>
      <div class="px-2 py-3 bg-slate-900/40">
        <span class={[
          "text-[10px] font-bold uppercase tracking-wider",
          if(@completion["status"] == "ok", do: "text-green-400", else: "text-red-400")
        ]}>
          {if @completion["status"] == "ok", do: "response", else: "error"}
        </span>
        <pre class="ps-2 text-xs text-slate-300 whitespace-pre-wrap break-words font-mono leading-relaxed">{@completion["result"]}</pre>
      </div>
    </div>
    """
  end

  defp messages(nil), do: []
  defp messages(msgs) when is_list(msgs), do: msgs
  defp messages(_), do: []
end
