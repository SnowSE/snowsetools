defmodule SnowSeToolsWeb.Admin.SnowCacheComponent do
  use SnowSeToolsWeb, :live_component

  alias SnowSeTools.Snow.SnowCourseCacheDomainManager

  def update(%{terms: terms} = assigns, socket) do
    socket =
      socket
      |> assign(Map.delete(assigns, :terms))
      |> assign(:terms, terms)
      |> assign(:snapshot_error, nil)
      |> base_assigns()

    {:ok, socket}
  end

  def update(%{sync_result: result} = assigns, socket) do
    socket =
      socket
      |> assign(Map.delete(assigns, :sync_result))
      |> apply_sync_result(result)
      |> base_assigns()

    {:ok, socket}
  end

  def update(%{snapshot_error: reason} = assigns, socket) do
    socket =
      socket
      |> assign(Map.delete(assigns, :snapshot_error))
      |> assign(:snapshot_error, reason)
      |> base_assigns()

    {:ok, socket}
  end

  def update(assigns, socket) do
    socket =
      socket
      |> assign(assigns)
      |> base_assigns()

    {:ok, socket}
  end

  def handle_event("toggle_term", %{"term_code" => term_code}, socket) do
    expanded_term_code =
      if socket.assigns.expanded_term_code == term_code do
        nil
      else
        term_code
      end

    {:noreply, assign(socket, :expanded_term_code, expanded_term_code)}
  end

  def handle_event("open_sync_modal", %{"mode" => mode, "term_code" => term_code}, socket) do
    {:noreply,
     socket
     |> assign(
       modal_open?: true,
       sync_mode: mode,
       sync_term_code: term_code,
       sync_message: nil,
       sync_error: nil,
       sync_form: to_form(%{"jwt_token" => ""}, as: :sync)
     )}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, close_modal(socket)}
  end

  def handle_event("sync", %{"sync" => %{"jwt_token" => jwt_token}}, socket) do
    jwt_token = String.trim(jwt_token || "")

    if jwt_token == "" do
      {:noreply, assign(socket, :sync_error, "Paste your JWT before syncing.")}
    else
      case socket.assigns.sync_mode do
        "courses" ->
          SnowCourseCacheDomainManager.sync_course_list(
            pid: self(),
            term_code: socket.assigns.sync_term_code,
            jwt_token: jwt_token
          )

          {:noreply,
           socket
           |> assign(:syncing, true)
           |> assign(:sync_error, nil)
           |> assign(:sync_message, nil)}

        "rosters" ->
          SnowCourseCacheDomainManager.sync_term_rosters(
            pid: self(),
            term_code: socket.assigns.sync_term_code,
            jwt_token: jwt_token
          )

          {:noreply,
           socket
           |> assign(:syncing, true)
           |> assign(:sync_error, nil)
           |> assign(:sync_message, nil)}

        _ ->
          {:noreply, assign(socket, :sync_error, "Unknown sync action.")}
      end
    end
  end

  def render(assigns) do
    ~H"""
    <section
      id={@id}
      class="rounded-2xl border border-slate-800 bg-slate-900/70 p-5 shadow-xl shadow-slate-950/20"
    >
      <div class="mb-5 flex flex-wrap items-start justify-between gap-4">
        <div class="space-y-2">
          <h2 class="text-lg font-semibold text-slate-100">Cached Snow semesters</h2>
          <p class="max-w-3xl text-sm leading-6 text-slate-400">
            Download class lists from my.snow.edu, then expand a semester to inspect the cached tracked courses and refresh their rosters.
          </p>
        </div>
      </div>

      <div class="mb-5 grid gap-3 md:grid-cols-2">
        <%= for shortcut <- semester_shortcuts() do %>
          <article class="rounded-2xl border border-slate-800 bg-slate-950/50 p-4">
            <div class="space-y-2">
              <div class="flex flex-wrap items-center gap-2">
                <h3 class="text-sm font-semibold uppercase tracking-[0.22em] text-slate-400">
                  {shortcut.label}
                </h3>
                <span class="rounded-full bg-slate-800 px-2.5 py-1 text-xs font-medium text-slate-300">
                  {shortcut.term_name}
                </span>
              </div>
              <p class="text-sm text-slate-500">Term code {shortcut.term_code}</p>
            </div>

            <div class="mt-4 flex flex-wrap gap-2">
              <button
                type="button"
                phx-click="open_sync_modal"
                phx-target={@myself}
                phx-value-mode="courses"
                phx-value-term_code={shortcut.term_code}
                class="rounded-xl bg-indigo-500 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-indigo-400"
              >
                Sync Class List
              </button>
              <button
                type="button"
                phx-click="open_sync_modal"
                phx-target={@myself}
                phx-value-mode="rosters"
                phx-value-term_code={shortcut.term_code}
                disabled={not courses_cached_for_term?(terms: @terms, term_code: shortcut.term_code)}
                class="rounded-xl border border-indigo-500/30 bg-indigo-500/10 px-4 py-2.5 text-sm font-semibold text-indigo-100 transition hover:bg-indigo-500/20 disabled:cursor-not-allowed disabled:border-slate-700 disabled:bg-slate-900 disabled:text-slate-500"
              >
                Sync Rosters
              </button>
            </div>

            <p class="mt-3 text-xs leading-5 text-slate-500">
              Roster sync becomes available after the class list is cached for this semester.
            </p>
          </article>
        <% end %>
      </div>

      <%= if @sync_message do %>
        <div class="mb-4 rounded-xl border border-emerald-500/20 bg-emerald-500/10 px-4 py-3 text-sm font-medium text-emerald-200">
          {@sync_message}
        </div>
      <% end %>

      <%= if @sync_error do %>
        <div class="mb-4 rounded-xl border border-rose-500/20 bg-rose-500/10 px-4 py-3 text-sm font-medium text-rose-200">
          {@sync_error}
        </div>
      <% end %>

      <%= if @snapshot_error do %>
        <div class="mb-4 rounded-xl border border-amber-500/20 bg-amber-500/10 px-4 py-3 text-sm font-medium text-amber-100">
          Unable to load cached semesters: {@snapshot_error}
        </div>
      <% end %>

      <%= if @terms == [] do %>
        <div class="rounded-xl border border-slate-800 bg-slate-950/50 px-4 py-6 text-sm text-slate-400">
          No semesters cached yet. Use the semester shortcuts above to download the current or next term.
        </div>
      <% else %>
        <div class="space-y-3">
          <%= for term <- @terms do %>
            <article
              id={"snow-term-#{term["term_code"]}"}
              class="overflow-hidden rounded-2xl border border-slate-800 bg-slate-950/40"
            >
              <button
                type="button"
                phx-click="toggle_term"
                phx-target={@myself}
                phx-value-term_code={term["term_code"]}
                class="flex w-full items-start justify-between gap-4 px-4 py-4 text-left transition hover:bg-slate-900/60"
              >
                <div class="space-y-1">
                  <div class="flex flex-wrap items-center gap-2">
                    <h3 class="text-base font-semibold text-slate-100">{term["term_name"]}</h3>
                    <span class="rounded-full bg-slate-800 px-2.5 py-1 text-xs font-medium text-slate-300">
                      {term["course_count"]} tracked courses
                    </span>
                    <span class="rounded-full bg-slate-800 px-2.5 py-1 text-xs font-medium text-slate-300">
                      {term["roster_count"]} cached rosters
                    </span>
                  </div>
                  <p class="text-xs text-slate-500">
                    Term code {term["term_code"]} · cached {term["cached_at"]}
                  </p>
                </div>
                <span class="mt-1 rounded-full border border-slate-700 px-2.5 py-1 text-xs font-semibold text-slate-300">
                  {if(@expanded_term_code == term["term_code"], do: "Collapse", else: "Expand")}
                </span>
              </button>

              <%= if @expanded_term_code == term["term_code"] do %>
                <div class="border-t border-slate-800 px-4 py-4">
                  <div class="mb-4 flex flex-wrap items-center justify-between gap-3">
                    <p class="text-sm text-slate-300">
                      These are the courses cached locally for this semester.
                    </p>
                    <div class="flex gap-2">
                      <button
                        type="button"
                        phx-click="open_sync_modal"
                        phx-target={@myself}
                        phx-value-mode="courses"
                        phx-value-term_code={term["term_code"]}
                        class="rounded-xl border border-slate-700 px-4 py-2 text-sm font-semibold text-slate-200 transition hover:bg-slate-900"
                      >
                        Refresh Class List
                      </button>
                      <button
                        type="button"
                        phx-click="open_sync_modal"
                        phx-target={@myself}
                        phx-value-mode="rosters"
                        phx-value-term_code={term["term_code"]}
                        disabled={term["course_count"] == 0}
                        class="rounded-xl border border-indigo-500/30 bg-indigo-500/10 px-4 py-2 text-sm font-semibold text-indigo-100 transition hover:bg-indigo-500/20 disabled:cursor-not-allowed disabled:border-slate-700 disabled:bg-slate-900 disabled:text-slate-500"
                      >
                        Refresh All Rosters
                      </button>
                    </div>
                  </div>

                  <%= if term["courses"] == [] do %>
                    <div class="rounded-xl border border-dashed border-slate-800 px-4 py-5 text-sm text-slate-400">
                      No courses cached for this semester yet.
                    </div>
                  <% else %>
                    <div class="space-y-2">
                      <%= for course <- term["courses"] do %>
                        <article
                          id={"snow-course-#{term["term_code"]}-#{course["crn"]}"}
                          class="rounded-xl border border-slate-800 bg-slate-950/60 px-4 py-3"
                        >
                          <div class="flex flex-wrap items-start justify-between gap-3">
                            <div class="space-y-1">
                              <div class="flex flex-wrap items-center gap-2">
                                <span class="font-medium text-slate-100">
                                  {course["subject_code"]} {course["course_number"]} {course[
                                    "section_number"
                                  ]}
                                </span>
                                <span class="rounded-full bg-slate-800 px-2.5 py-1 text-xs text-slate-300">
                                  CRN {course["crn"]}
                                </span>
                              </div>
                              <p class="text-sm text-slate-300">{course["course_name"]}</p>
                              <p class="text-xs text-slate-500">
                                {primary_instructor_text(course["primary_instructor_name"])}
                              </p>
                            </div>
                            <div class="text-right">
                              <p class="text-sm font-semibold text-slate-100">
                                {course["roster_count"]} roster rows
                              </p>
                              <p class="text-xs text-slate-500">Cached {course["cached_at"]}</p>
                            </div>
                          </div>
                        </article>
                      <% end %>
                    </div>
                  <% end %>
                </div>
              <% end %>
            </article>
          <% end %>
        </div>
      <% end %>

      <%= if @modal_open? do %>
        <.modal id="snow-cache-sync-modal" on_close="close_modal" target={@myself}>
          <div class="space-y-5">
            <div class="space-y-2">
              <h3 class="text-xl font-semibold text-slate-100">
                {modal_title(@sync_mode, @sync_term_code, @terms)}
              </h3>
              <p class="text-sm leading-6 text-slate-300">
                {modal_description(@sync_mode, @sync_term_code, @terms)}
              </p>
            </div>

            <.form
              for={@sync_form}
              id="snow-cache-sync-form"
              phx-submit="sync"
              phx-target={@myself}
              class="space-y-4"
            >
              <label class="block space-y-2">
                <span class="block text-sm font-medium text-slate-300">JWT token</span>
                <input
                  type="password"
                  name={@sync_form[:jwt_token].name}
                  value={@sync_form[:jwt_token].value}
                  autocomplete="off"
                  class="w-full rounded-xl border border-slate-700 bg-slate-950/60 px-4 py-3 text-slate-100 placeholder:text-slate-500 outline-none transition focus:border-indigo-500 focus:ring-2 focus:ring-indigo-500/20"
                  placeholder="Paste JWT from my.snow.edu"
                />
              </label>

              <div class="flex justify-end gap-3">
                <button
                  type="button"
                  phx-click="close_modal"
                  phx-target={@myself}
                  class="rounded-xl border border-slate-700 px-4 py-2.5 text-sm font-semibold text-slate-300 transition hover:bg-slate-800"
                >
                  Cancel
                </button>
                <button
                  type="submit"
                  disabled={@syncing}
                  class="rounded-xl bg-indigo-500 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-indigo-400 disabled:cursor-not-allowed disabled:bg-slate-700 disabled:text-slate-400"
                >
                  <%= if @syncing do %>
                    Syncing...
                  <% else %>
                    {modal_button_text(@sync_mode)}
                  <% end %>
                </button>
              </div>
            </.form>
          </div>
        </.modal>
      <% end %>
    </section>
    """
  end

  defp base_assigns(socket) do
    socket
    |> assign_new(:terms, fn -> [] end)
    |> assign_new(:expanded_term_code, fn -> nil end)
    |> assign_new(:modal_open?, fn -> false end)
    |> assign_new(:sync_mode, fn -> nil end)
    |> assign_new(:sync_term_code, fn -> nil end)
    |> assign_new(:sync_message, fn -> nil end)
    |> assign_new(:sync_error, fn -> nil end)
    |> assign_new(:snapshot_error, fn -> nil end)
    |> assign_new(:syncing, fn -> false end)
    |> assign_new(:sync_form, fn -> to_form(%{"jwt_token" => ""}, as: :sync) end)
  end

  defp apply_sync_result(socket, {:ok, message}) do
    socket
    |> assign(:sync_message, message)
    |> assign(:sync_error, nil)
    |> assign(:syncing, false)
    |> assign(:modal_open?, false)
    |> assign(:sync_mode, nil)
    |> assign(:sync_term_code, nil)
    |> assign(:sync_form, to_form(%{"jwt_token" => ""}, as: :sync))
  end

  defp apply_sync_result(socket, {:error, reason}) do
    assign(socket,
      sync_error: reason,
      sync_message: nil,
      syncing: false
    )
  end

  defp close_modal(socket) do
    assign(socket,
      modal_open?: false,
      sync_error: nil,
      sync_message: nil,
      syncing: false,
      sync_form: to_form(%{"jwt_token" => ""}, as: :sync)
    )
  end

  defp modal_button_text("courses"), do: "Sync Class List"
  defp modal_button_text("rosters"), do: "Sync Rosters"
  defp modal_button_text(_), do: "Sync"

  defp modal_title("courses", term_code, terms) do
    "Refresh class list for #{term_display_name(terms, term_code)}"
  end

  defp modal_title("rosters", term_code, terms) do
    "Refresh rosters for #{term_display_name(terms, term_code)}"
  end

  defp modal_title(_, _term_code, _terms), do: "Refresh cached Snow data"

  defp modal_description("courses", term_code, terms) do
    "This will download the current class list for #{term_display_name(terms, term_code)}."
  end

  defp modal_description("rosters", term_code, terms) do
    "This will refresh the cached rosters for every tracked course in #{term_display_name(terms, term_code)}."
  end

  defp modal_description(_, _term_code, _terms),
    do: "Paste the JWT cookie from my.snow.edu to continue."

  defp term_display_name(terms, term_code) do
    case Enum.find_value(terms, fn term ->
           if term["term_code"] == term_code, do: term["term_name"]
         end) do
      nil -> term_code || "the selected semester"
      name -> name
    end
  end

  defp semester_shortcuts do
    current_term_code = current_term_code(Date.utc_today())
    next_term_code = next_term_code(current_term_code)

    [
      %{
        label: "Current semester",
        term_code: current_term_code,
        term_name: term_name_from_code(current_term_code)
      },
      %{
        label: "Next semester",
        term_code: next_term_code,
        term_name: term_name_from_code(next_term_code)
      }
    ]
  end

  defp courses_cached_for_term?(terms: terms, term_code: term_code) do
    Enum.any?(terms, fn term -> term["term_code"] == term_code and term["course_count"] > 0 end)
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

  defp primary_instructor_text(nil), do: "No instructor cached"
  defp primary_instructor_text(""), do: "No instructor cached"
  defp primary_instructor_text(name), do: name
end
