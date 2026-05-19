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
      <%= if thinking = non_empty(@completion["thinking"]) do %>
        <div class="px-2 py-3 border-t border-slate-700/60 bg-amber-950/20">
          <button
            type="button"
            phx-click={
              JS.toggle(to: "#thinking-body-#{@completion["id"]}")
              |> JS.toggle_class("rotate-180", to: "#thinking-chevron-#{@completion["id"]}")
            }
            class="flex items-center gap-2 cursor-pointer hover:opacity-80 transition-opacity"
          >
            <span class="text-[10px] font-bold uppercase tracking-wider text-amber-400">
              thinking
            </span>
            <span
              id={"thinking-chevron-#{@completion["id"]}"}
              class="hero-chevron-down size-3 text-amber-500 transition-transform"
            />
          </button>
          <pre
            id={"thinking-body-#{@completion["id"]}"}
            class="hidden ps-2 mt-1 text-xs text-amber-200/70 whitespace-pre-wrap break-words font-mono leading-relaxed"
          >{thinking}</pre>
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

  defp non_empty(nil), do: nil
  defp non_empty(""), do: nil
  defp non_empty(str), do: str
end
