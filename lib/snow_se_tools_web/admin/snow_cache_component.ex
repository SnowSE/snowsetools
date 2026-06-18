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

  def handle_event("open_sync_modal", %{"term_code" => term_code}, socket) do
    {:noreply,
     socket
     |> assign(
       modal_open?: true,
       sync_mode: "courses",
       sync_term_code: term_code,
       sync_message: nil,
       sync_error: nil,
       jwt_token: ""
     )}
  end

  def handle_event("close_modal", _params, socket) do
    {:noreply, close_modal(socket)}
  end

  def handle_event("snow_jwt_submit", %{"snow_jwt_copy" => %{"jwt_token" => jwt_token}}, socket) do
    jwt_token = String.trim(jwt_token || "")

    if jwt_token == "" do
      {:noreply, assign(socket, :sync_error, "Paste your JWT before syncing.")}
    else
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
          <h2 class="text-lg font-semibold text-slate-200">Cached Snow semesters</h2>
        </div>
      </div>

      <div class="mb-5 flex flex-col gap-3">
        <%= for shortcut <- semester_shortcuts(terms: @terms) do %>
          <article class="rounded-2xl border border-slate-800 bg-slate-950/50 p-4">
            <div class="space-y-2">
              <h3 class="text-base font-semibold text-slate-100">{shortcut.term_name}</h3>
              <p class="text-sm text-slate-500">Term code {shortcut.term_code}</p>
            </div>

            <div class="mt-4 flex flex-wrap gap-2">
              <button
                type="button"
                phx-click="open_sync_modal"
                phx-target={@myself}
                phx-value-term_code={shortcut.term_code}
                class="rounded-xl bg-indigo-500 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-indigo-400"
              >
                Sync Class List
              </button>
            </div>
          </article>
        <% end %>

        <%= if semester_shortcuts(terms: @terms) == [] do %>
          <div class="rounded-xl border border-slate-800 bg-slate-950/50 px-4 py-5 text-sm text-slate-400">
            The current and next semesters are already cached locally.
          </div>
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
                    <button
                      type="button"
                      phx-click="open_sync_modal"
                      phx-target={@myself}
                      phx-value-term_code={term["term_code"]}
                      class="rounded-xl border border-slate-700 px-4 py-2 text-sm font-semibold text-slate-200 transition hover:bg-slate-900"
                    >
                      Refresh Class List
                    </button>
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
                            <p class="text-xs text-slate-500">Cached {course["cached_at"]}</p>
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
                {modal_title(term_code: @sync_term_code, terms: @terms)}
              </h3>
              <p class="text-sm leading-6 text-slate-300">
                {modal_description(term_code: @sync_term_code, terms: @terms)}
              </p>
            </div>

            <.live_component
              module={SnowSeToolsWeb.Snow.SnowJwtCopy}
              id="snow-jwt-copy"
              target={@myself}
              submit_event="snow_jwt_submit"
              label="JWT token"
              value=""
              submit_label="Sync Class List"
              show_helper={true}
            />

            <div class="flex justify-end gap-3">
              <button
                type="button"
                phx-click="close_modal"
                phx-target={@myself}
                class="rounded-xl border border-slate-700 px-4 py-2.5 text-sm font-semibold text-slate-300 transition hover:bg-slate-800"
              >
                Cancel
              </button>
            </div>
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
    |> assign_new(:jwt_token, fn -> nil end)
    |> assign_new(:snapshot_error, fn -> nil end)
    |> assign_new(:syncing, fn -> false end)
  end

  defp apply_sync_result(socket, {:ok, message}) do
    socket
    |> assign(:sync_message, message)
    |> assign(:sync_error, nil)
    |> assign(:syncing, false)
    |> assign(:modal_open?, false)
    |> assign(:sync_mode, nil)
    |> assign(:sync_term_code, nil)
    |> assign(:jwt_token, nil)
  end

  defp apply_sync_result(socket, {:error, reason}) do
    assign(socket,
      sync_error: reason,
      sync_message: nil,
      syncing: false,
      jwt_token: nil
    )
  end

  defp close_modal(socket) do
    assign(socket,
      modal_open?: false,
      sync_error: nil,
      sync_message: nil,
      syncing: false,
      jwt_token: nil
    )
  end

  defp modal_title(term_code: term_code, terms: terms) do
    "Refresh class list for #{term_display_name(terms: terms, term_code: term_code)}"
  end

  defp modal_description(term_code: term_code, terms: terms) do
    "This will download the current class list for #{term_display_name(terms: terms, term_code: term_code)}."
  end

  defp term_display_name(terms: terms, term_code: term_code) do
    case Enum.find_value(terms, fn term ->
           if term["term_code"] == term_code, do: term["term_name"]
         end) do
      nil -> term_code || "the selected semester"
      name -> name
    end
  end

  defp semester_shortcuts(terms: terms) do
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

  defp primary_instructor_text(nil), do: "No instructor cached"
  defp primary_instructor_text(""), do: "No instructor cached"
  defp primary_instructor_text(name), do: name
end
