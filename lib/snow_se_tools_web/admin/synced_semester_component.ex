defmodule SnowSeToolsWeb.Admin.SyncedSemesterComponent do
  use SnowSeToolsWeb, :live_component

  def update(assigns, socket) do
    {:ok, assign(socket, assigns)}
  end

  attr :term, :map, required: true
  attr :expanded?, :boolean, default: false
  attr :pending_delete_term, :any, default: nil
  attr :target, :any, required: true

  def render(assigns) do
    ~H"""
    <article
      id={"snow-term-#{@term["term_code"]}"}
      class="border-b border-slate-800 py-3 last:border-b-0"
    >
      <button
        type="button"
        phx-click="toggle_term"
        phx-target={@target}
        phx-value-term_code={@term["term_code"]}
        class="flex w-full items-center justify-between gap-4 text-left"
      >
        <div>
          <div class="flex flex-wrap items-center gap-2">
            <h3 class="text-sm font-semibold text-slate-100">{@term["term_name"]}</h3>
            <span class="text-xs text-slate-500">{@term["term_code"]}</span>
          </div>
          <p class="text-xs text-slate-500">
            {@term["course_count"]} tracked courses · cached {relative_time(@term["cached_at"])}
          </p>
        </div>
        <span class="text-xs font-semibold text-slate-400">
          {if(@expanded?, do: "Collapse", else: "Expand")}
        </span>
      </button>

      <%= if @expanded? do %>
        <div class="mt-3 space-y-3 pl-3">
          <div class="flex gap-2">
            <button
              type="button"
              phx-click="select_sync_term"
              phx-target={@target}
              phx-value-term_code={@term["term_code"]}
              class="rounded-lg border border-slate-700 px-3 py-2 text-sm font-semibold text-slate-300 transition hover:bg-slate-800"
            >
              Refresh class list
            </button>

            <button
              type="button"
              phx-click="request_delete_term"
              phx-target={@target}
              phx-value-term_code={@term["term_code"]}
              disabled={@pending_delete_term && @pending_delete_term.term_code != @term["term_code"]}
              class="rounded-lg border border-rose-800/50 bg-rose-500/10 px-3 py-2 text-sm font-semibold text-rose-300 transition hover:bg-rose-500/20 disabled:opacity-50"
            >
              Delete semester data
            </button>
          </div>

          <%= if @term["courses"] == [] do %>
            <p class="text-sm text-slate-500">No courses cached for this semester.</p>
          <% else %>
            <div class="divide-y divide-slate-800">
              <%= for course <- @term["courses"] do %>
                <div id={"snow-course-#{@term["term_code"]}-#{course["crn"]}"} class="py-2">
                  <div class="flex flex-wrap items-start justify-between gap-3">
                    <div>
                      <p class="text-sm font-medium text-slate-200">
                        {course["subject_code"]} {course["course_number"]} {course["section_number"]}
                      </p>
                      <p class="text-sm text-slate-400">{course["course_name"]}</p>
                      <p class="text-xs text-slate-500">
                        {primary_instructor_text(course["primary_instructor_name"])}
                      </p>
                    </div>
                    <span class="text-xs text-slate-500">CRN {course["crn"]}</span>
                  </div>
                </div>
              <% end %>
            </div>
          <% end %>
        </div>
      <% end %>
    </article>
    """
  end

  defp primary_instructor_text(nil), do: "No instructor cached"
  defp primary_instructor_text(""), do: "No instructor cached"
  defp primary_instructor_text(name), do: name

  defp relative_time(datetime_str) do
    with {:ok, dt, _} <- DateTime.from_iso8601(datetime_str) do
      now = DateTime.utc_now()
      diff = DateTime.diff(now, dt)

      cond do
        diff < 60 -> "just now"
        diff < 3600 -> "#{div(diff, 60)} min ago"
        diff < 86400 -> "#{div(diff, 3600)} hours ago"
        diff < 2_592_000 -> "#{div(diff, 86400)} days ago"
        diff < 31_536_000 -> "#{div(diff, 2_592_000)} months ago"
        true -> "#{div(diff, 31_536_000)} years ago"
      end
    else
      _ -> datetime_str
    end
  end
end
