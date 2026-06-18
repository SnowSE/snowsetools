defmodule SnowSeToolsWeb.Admin.NewSemesterSyncComponent do
  use SnowSeToolsWeb, :live_component

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  attr :terms, :list, required: true
  attr :sync_form, Phoenix.HTML.Form, required: true
  attr :sync_term_code, :string, default: nil
  attr :jwt_token, :string, default: nil
  attr :syncing, :boolean, default: false
  attr :target, :any, required: true

  def render(assigns) do
    ~H"""
    <section class="border-b border-slate-800 pb-5">
      <.form
        for={@sync_form}
        id="snow-sync-form"
        phx-change="select_sync_term"
        phx-submit="sync_classes_for_term"
        phx-target={@target}
        class="grid gap-4 lg:grid-cols-[minmax(0,18rem)_minmax(0,1fr)_auto]"
      >
        <label class="space-y-2">
          <span class="block text-sm font-medium text-slate-300">Sync class list</span>
          <select
            id="snow-term-selector"
            name="snow_sync[term_code]"
            disabled={@syncing}
            class="w-full rounded-lg border border-slate-700 bg-slate-950/70 px-3 py-2.5 text-sm text-slate-100 outline-none transition focus:border-indigo-500 disabled:cursor-not-allowed disabled:opacity-60"
          >
            <option value="">Choose semester</option>
            <%= for shortcut <- semester_shortcuts(terms: @terms) do %>
              <option value={shortcut.term_code} selected={@sync_term_code == shortcut.term_code}>
                {shortcut.label}: {shortcut.term_name}
              </option>
            <% end %>
          </select>
        </label>

        <div>
          <%= if @sync_term_code do %>
            <div class="space-y-2">
              <p class="text-sm text-slate-400">
                {term_display_name(terms: @terms, term_code: @sync_term_code)}
              </p>
              <.live_component
                module={SnowSeToolsWeb.Snow.SnowJwtCopy}
                id="snow-jwt-copy"
                label="JWT token"
                name="snow_sync[jwt_token]"
                placeholder="Paste JWT from my.snow.edu"
                value={@jwt_token || ""}
                show_helper={true}
              />
            </div>
          <% else %>
            <div class="flex min-h-20 items-center text-sm text-slate-500">
              Unsynced current and next terms appear in the dropdown.
            </div>
          <% end %>
        </div>

        <div class="flex items-end justify-end gap-2">
          <%= if @sync_term_code do %>
            <button
              type="button"
              phx-click="cancel_sync"
              phx-target={@target}
              class="rounded-lg border border-slate-700 px-3 py-2 text-sm font-semibold text-slate-300 transition hover:bg-slate-800"
            >
              Cancel
            </button>
            <button
              type="submit"
              disabled={@syncing}
              class="rounded-lg bg-indigo-500 px-4 py-2 text-sm font-semibold text-white transition hover:bg-indigo-400 disabled:cursor-not-allowed disabled:bg-slate-700 disabled:text-slate-400"
            >
              {if(@syncing, do: "Syncing...", else: "Sync")}
            </button>
          <% end %>
          <%= if @syncing do %>
            <svg
              class="inline-block h-4 w-4 animate-spin -ml-1 mr-2"
              xmlns="http://www.w3.org/2000/svg"
              fill="none"
              viewBox="0 0 24 24"
            >
              <circle
                class="opacity-25"
                cx="12"
                cy="12"
                r="10"
                stroke="currentColor"
                stroke-width="4"
              >
              </circle>
              <path
                class="opacity-75"
                fill="currentColor"
                d="M4 12a8 8 0 018-8V0C5.373 0 0 5.373 0 12h4zm2 5.291A7.962 7.962 0 014 12H0c0 3.042 1.135 5.824 3 7.938l3-2.647z"
              >
              </path>
            </svg>
          <% end %>
        </div>
      </.form>
    </section>
    """
  end

  defp semester_shortcuts(terms: terms) do
    current_term_code = current_term_code(Date.utc_today())
    next_term_code = next_term_code(current_term_code)

    [
      %{
        label: "Current",
        term_code: current_term_code,
        term_name: term_name_from_code(current_term_code)
      },
      %{
        label: "Next",
        term_code: next_term_code,
        term_name: term_name_from_code(next_term_code)
      }
    ]
    |> Enum.reject(&term_synced?(terms: terms, term_code: &1.term_code))
  end

  defp term_synced?(terms: terms, term_code: term_code) do
    Enum.any?(terms, &(&1["term_code"] == term_code))
  end

  defp current_term_code(%Date{month: month, year: year}) do
    semester_code =
      cond do
        month in 1..5 -> "10"
        month in 6..8 -> "30"
        true -> "40"
      end

    "#{year}#{semester_code}"
  end

  defp next_term_code(term_code) when is_binary(term_code) do
    <<year::binary-size(4), semester_code::binary-size(2)>> = term_code

    case semester_code do
      "10" -> "#{year}30"
      "30" -> "#{year}40"
      "40" -> "#{String.to_integer(year) + 1}10"
      _ -> term_code
    end
  end

  defp term_name_from_code(term_code) when is_binary(term_code) do
    <<year::binary-size(4), semester_code::binary-size(2)>> = term_code

    semester_name =
      case semester_code do
        "10" -> "Spring"
        "30" -> "Summer"
        "40" -> "Fall"
        _ -> "Unknown"
      end

    "#{semester_name} #{year}"
  end

  defp term_display_name(terms: terms, term_code: term_code) do
    case Enum.find_value(terms, fn term ->
           if term["term_code"] == term_code, do: term["term_name"]
         end) do
      nil -> "#{term_name_from_code(term_code)} (#{term_code})"
      name -> "#{name} (#{term_code})"
    end
  end
end
