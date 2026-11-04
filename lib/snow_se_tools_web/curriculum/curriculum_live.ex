defmodule SnowSeToolsWeb.Curriculum.CurriculumLive do
  @moduledoc """
  The curriculum map: how skills, course outcomes and ABET outcomes run
  through an academic program's courses, in the order of its plan.

  Anyone approved can read it; members of `curriculum_admin` can edit skills
  and links, run the master-syllabus and AI review, accept its suggestions and
  import the ABET matrix.

  Everything goes through `CurriculumDomainManager`: the page asks for the
  map and gets it back as a message, and asks again whenever the manager says
  the map changed.
  """

  use SnowSeToolsWeb, :live_view

  require Logger

  alias SnowSeTools.Curriculum.{CurriculumDomainManager, CurriculumMap, CurriculumPubSub}
  alias SnowSeToolsWeb.Curriculum.{AbetView, CourseView, GraphView, SkillsView}
  alias SnowSeToolsWeb.Curriculum.{SuggestionsView, ThreadsView}

  on_mount {SnowSeToolsWeb.UserAuth, {:ensure_access, :curriculum}}
  on_mount SnowSeToolsWeb.Curriculum.CurriculumAccess

  @tabs [
    threads: "Skill threads",
    abet: "ABET coverage",
    graph: "Prerequisite map",
    skills: "Skills",
    suggestions: "Suggestions"
  ]

  @empty_data %{
    skills: [],
    dependencies: [],
    links: [],
    master_syllabi: [],
    outcomes: [],
    abet_outcomes: [],
    coverage: [],
    last_import: nil,
    pending: []
  }

  def mount(_params, _session, socket) do
    if connected?(socket) do
      CurriculumPubSub.subscribe()
      CurriculumDomainManager.request_map(pid: self())
    end

    socket =
      socket
      |> assign(:page_title, "Curriculum map")
      |> assign(:tabs, @tabs)
      |> assign(:loaded?, false)
      |> assign(:data, @empty_data)
      |> assign(:programs, [])
      |> assign(:program, nil)
      |> assign(:courses, [])
      |> assign(:requested_program_id, nil)
      |> assign(:run_status, %{running?: false, phase: nil, run: nil})
      |> assign(:threads_filter, %{"category" => "", "query" => "", "show_unused" => "false"})
      |> assign(:editing_skill_id, nil)
      |> assign(:abet_upload, nil)

    socket =
      if socket.assigns.curriculum_editor? do
        allow_upload(socket, :abet_matrix,
          accept: ~w(.xlsx),
          max_entries: 1,
          max_file_size: 10_000_000,
          auto_upload: true,
          progress: &handle_abet_progress/3
        )
      else
        socket
      end

    {:ok, socket}
  end

  def handle_params(params, _uri, socket) do
    socket =
      socket
      |> assign(:tab, tab_from(params["tab"]))
      |> assign(:overlay, overlay_from(params["overlay"]))
      |> assign(:course_key, course_key_from(socket.assigns.live_action, params))
      |> assign(:requested_program_id, params["program"])
      |> select_program()

    {:noreply, assign(socket, :page_title, page_title(socket.assigns))}
  end

  def handle_event("select_program", %{"program" => program_id}, socket) do
    {:noreply, push_patch(socket, to: curriculum_path(socket.assigns.nav, program: program_id))}
  end

  def handle_event("set_overlay", %{"overlay" => overlay}, socket) do
    {:noreply,
     push_patch(socket, to: curriculum_path(socket.assigns.nav, tab: :graph, overlay: overlay))}
  end

  def handle_event("filter_threads", params, socket) do
    filter = Map.take(params, ["category", "query", "show_unused"])
    {:noreply, assign(socket, :threads_filter, Map.merge(socket.assigns.threads_filter, filter))}
  end

  def handle_event("curriculum-edit:start_run", %{"kind" => kind}, socket) do
    kind = if kind == "syllabi_only", do: :syllabi_only, else: :full

    case socket.assigns.program do
      nil ->
        {:noreply, put_flash(socket, :error, "Pick an academic program first.")}

      program ->
        CurriculumDomainManager.start_run(
          pid: self(),
          program_id: program["id"],
          kind: kind,
          started_by: socket.assigns.current_user.email
        )

        {:noreply, socket}
    end
  end

  def handle_event("curriculum-edit:accept", %{"suggestion_id" => id} = params, socket) do
    CurriculumDomainManager.accept_suggestions(
      pid: self(),
      ids: [id],
      decided_by: socket.assigns.current_user.email,
      levels: %{id => params["level"]}
    )

    {:noreply, socket}
  end

  def handle_event("curriculum-edit:reject", %{"id" => id}, socket) do
    CurriculumDomainManager.reject_suggestions(
      pid: self(),
      ids: [id],
      decided_by: socket.assigns.current_user.email
    )

    {:noreply, socket}
  end

  def handle_event("curriculum-edit:accept_group", %{"ids" => ids}, socket) do
    CurriculumDomainManager.accept_suggestions(
      pid: self(),
      ids: String.split(ids, ","),
      decided_by: socket.assigns.current_user.email,
      levels: %{}
    )

    {:noreply, socket}
  end

  def handle_event("curriculum-edit:reject_group", %{"ids" => ids}, socket) do
    CurriculumDomainManager.reject_suggestions(
      pid: self(),
      ids: String.split(ids, ","),
      decided_by: socket.assigns.current_user.email
    )

    {:noreply, socket}
  end

  def handle_event("curriculum-edit:edit_skill", %{"id" => id}, socket) do
    {:noreply, assign(socket, :editing_skill_id, id)}
  end

  def handle_event("curriculum-edit:cancel_skill", _params, socket) do
    {:noreply, assign(socket, :editing_skill_id, nil)}
  end

  def handle_event("curriculum-edit:save_skill", %{"skill" => attrs}, socket) do
    attrs = Map.update(attrs, "builds_on_ids", [], &List.wrap/1)

    case attrs["id"] do
      id when id in [nil, ""] ->
        CurriculumDomainManager.create_skill(pid: self(), attrs: attrs)

      id ->
        CurriculumDomainManager.update_skill(pid: self(), id: id, attrs: attrs)
    end

    {:noreply, assign(socket, :editing_skill_id, nil)}
  end

  def handle_event("curriculum-edit:delete_skill", %{"id" => id}, socket) do
    CurriculumDomainManager.delete_skill(pid: self(), id: id)
    {:noreply, assign(socket, :editing_skill_id, nil)}
  end

  def handle_event("curriculum-edit:save_link", %{"link" => link}, socket) do
    if link["skill_id"] in [nil, ""] do
      {:noreply, put_flash(socket, :error, "Pick a skill to link.")}
    else
      CurriculumDomainManager.set_course_skill(
        pid: self(),
        link: link,
        updated_by: socket.assigns.current_user.email
      )

      {:noreply, socket}
    end
  end

  def handle_event("curriculum-edit:remove_link", link, socket) do
    CurriculumDomainManager.remove_course_skill(pid: self(), link: link)
    {:noreply, socket}
  end

  def handle_event("curriculum-edit:abet_validate", _params, socket) do
    {:noreply, socket}
  end

  def handle_event(
        "curriculum-edit:abet_sheets",
        %{"slo_sheet" => slo, "criteria_sheet" => criteria},
        socket
      ) do
    case socket.assigns.abet_upload do
      %{binary: binary, preview: %{file_name: file_name}} ->
        CurriculumDomainManager.preview_abet_matrix(
          pid: self(),
          xlsx: binary,
          file_name: file_name,
          sheets: %{slo_sheet: slo, criteria_sheet: criteria}
        )

        {:noreply, socket}

      _no_workbook ->
        {:noreply, socket}
    end
  end

  def handle_event("curriculum-edit:abet_cancel", _params, socket) do
    {:noreply, assign(socket, :abet_upload, nil)}
  end

  def handle_event("curriculum-edit:abet_import", _params, socket) do
    case socket.assigns.abet_upload do
      %{binary: binary, preview: %{result: {:ok, _matrix}} = preview} ->
        CurriculumDomainManager.import_abet_matrix(
          pid: self(),
          xlsx: binary,
          file_name: preview.file_name,
          sheets: %{
            slo_sheet: preview.slo_sheet,
            criteria_sheet: blank_to_nil(preview.criteria_sheet)
          },
          imported_by: socket.assigns.current_user.email
        )

        {:noreply, assign(socket, :abet_upload, nil)}

      _nothing_importable ->
        {:noreply,
         put_flash(socket, :error, "Choose an ABET matrix workbook that reads cleanly first.")}
    end
  end

  def handle_event(event, _params, socket) do
    Logger.warning("CurriculumLive ignored an unhandled event event=#{event}")
    {:noreply, socket}
  end

  def handle_info({:curriculum, {:loaded, loaded}}, socket) do
    {:noreply,
     socket
     |> assign(:loaded?, true)
     |> assign(:data, loaded.data)
     |> assign(:programs, loaded.programs)
     |> assign(:run_status, loaded.run_status)
     |> select_program()}
  end

  def handle_info({:curriculum, {:load_failed, reason}}, socket) do
    {:noreply,
     put_flash(
       socket,
       :error,
       "The curriculum map could not be loaded: #{CurriculumDomainManager.format_reason(reason)}"
     )}
  end

  def handle_info({:curriculum, :changed}, socket) do
    CurriculumDomainManager.request_map(pid: self())
    {:noreply, socket}
  end

  def handle_info({:curriculum, {:run, status}}, socket) do
    {:noreply, assign(socket, :run_status, status)}
  end

  def handle_info({:curriculum, {:abet_preview, %{error: reason}}}, socket) do
    {:noreply, socket |> assign(:abet_upload, nil) |> put_flash(:error, reason)}
  end

  def handle_info({:curriculum, {:abet_preview, preview}}, socket) do
    case socket.assigns.abet_upload do
      %{binary: _binary} = upload ->
        {:noreply, assign(socket, :abet_upload, %{upload | preview: preview})}

      nil ->
        {:noreply, socket}
    end
  end

  def handle_info({:curriculum, {:action_result, {:ok, message}}}, socket) do
    {:noreply, put_flash(socket, :info, message)}
  end

  def handle_info({:curriculum, {:action_result, {:error, reason}}}, socket) do
    {:noreply, put_flash(socket, :error, CurriculumDomainManager.format_reason(reason))}
  end

  def handle_info(message, socket) do
    Logger.warning("CurriculumLive ignored an unhandled message #{inspect(message, limit: 5)}")
    {:noreply, socket}
  end

  defp handle_abet_progress(:abet_matrix, entry, socket) do
    if entry.done? do
      binary =
        consume_uploaded_entry(socket, entry, fn %{path: path} -> {:ok, File.read!(path)} end)

      CurriculumDomainManager.preview_abet_matrix(
        pid: self(),
        xlsx: binary,
        file_name: entry.client_name,
        sheets: %{}
      )

      {:noreply, assign(socket, :abet_upload, %{binary: binary, preview: nil})}
    else
      {:noreply, socket}
    end
  end

  defp select_program(socket) do
    programs = socket.assigns.programs
    requested = socket.assigns.requested_program_id

    program =
      Enum.find(programs, &(&1["id"] == requested)) ||
        Enum.find(programs, &(&1["name"] =~ ~r/software/i)) ||
        List.first(programs)

    courses =
      if program,
        do:
          CurriculumMap.titled_courses(
            courses: CurriculumMap.program_courses(program),
            master_syllabi: socket.assigns.data.master_syllabi
          ),
        else: []

    socket
    |> assign(:program, program)
    |> assign(:courses, courses)
    |> assign(:nav, %{program: program, tab: socket.assigns.tab, overlay: socket.assigns.overlay})
  end

  defp tab_from(tab) do
    Enum.find_value(@tabs, :threads, fn {key, _label} ->
      if Atom.to_string(key) == tab, do: key
    end)
  end

  defp overlay_from("skill:" <> id), do: {:skill, id}
  defp overlay_from("abet:" <> code), do: {:abet, code}
  defp overlay_from(_none), do: nil

  defp course_key_from(:course, %{"subject" => subject, "number" => number}),
    do: {String.upcase(subject), number}

  defp course_key_from(_action, _params), do: nil

  defp page_title(%{live_action: :course, course_key: {subject, number}}),
    do: "#{subject} #{number} · Curriculum"

  defp page_title(_assigns), do: "Curriculum map"

  defp blank_to_nil(""), do: nil
  defp blank_to_nil(value), do: value

  @doc "A link within the map that keeps the selected program (and graph overlay)."
  def curriculum_path(nav, overrides \\ []) do
    program_id = Keyword.get(overrides, :program, nav.program && nav.program["id"])
    tab = Keyword.get(overrides, :tab, nav.tab)
    overlay = Keyword.get(overrides, :overlay, overlay_param(nav.overlay))

    query =
      [
        program: program_id,
        tab: if(tab != :threads, do: tab),
        overlay: if(tab == :graph, do: overlay)
      ]
      |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)

    "/curriculum" <> if(query == [], do: "", else: "?" <> URI.encode_query(query))
  end

  def course_path(nav: nav, course: {subject, number}) do
    query = if nav.program, do: "?" <> URI.encode_query(program: nav.program["id"]), else: ""
    "/curriculum/courses/#{subject}/#{number}" <> query
  end

  defp overlay_param({:skill, id}), do: "skill:" <> id
  defp overlay_param({:abet, code}), do: "abet:" <> code
  defp overlay_param(_none), do: nil

  def render(assigns) do
    ~H"""
    <Layouts.app
      flash={@flash}
      current_user={@current_user}
      socket={@socket}
      current_path={@current_path}
    >
      <div class="flex min-h-full flex-col">
        <div class="shrink-0 border-b border-slate-700/60">
          <div class="mx-auto flex w-full max-w-[2000px] flex-wrap items-center gap-x-4 gap-y-2 px-3 py-2 sm:px-4">
            <h1 class="text-sm font-semibold text-slate-100">Curriculum map</h1>
            <form :if={@programs != []} id="curriculum-program-form" phx-change="select_program">
              <label class="sr-only" for="curriculum-program">Academic program</label>
              <select
                id="curriculum-program"
                name="program"
                class="rounded-md border border-slate-700 bg-slate-900 px-2 py-1 text-xs text-slate-200"
              >
                <option
                  :for={program <- @programs}
                  value={program["id"]}
                  selected={@program && program["id"] == @program["id"]}
                >
                  {program["name"]}
                </option>
              </select>
            </form>
            <span
              :if={@run_status.running?}
              id="curriculum-run-phase"
              class="inline-flex items-center gap-1.5 text-xs text-amber-200"
            >
              <.icon name="hero-arrow-path" class="size-3.5 animate-spin" /> {@run_status.phase}
            </span>
            <nav class="-mx-1 flex min-w-0 basis-full items-center gap-1 overflow-x-auto whitespace-nowrap sm:mx-0 sm:flex-1 sm:basis-auto sm:justify-end">
              <.link
                :for={{tab, label} <- @tabs}
                id={"curriculum-tab-#{tab}"}
                patch={curriculum_path(@nav, tab: tab)}
                class={[
                  "border-b-2 px-3 py-1.5 text-sm font-medium transition-colors",
                  @live_action == :index && @tab == tab && "border-indigo-400 text-indigo-300",
                  (@live_action != :index || @tab != tab) &&
                    "border-transparent text-slate-400 hover:border-slate-500 hover:text-slate-200"
                ]}
              >
                {label}
                <span
                  :if={tab == :suggestions and @data.pending != []}
                  class="ms-1 rounded-full bg-amber-500/20 px-1.5 text-xs text-amber-200"
                >
                  {length(@data.pending)}
                </span>
              </.link>
            </nav>
          </div>
        </div>

        <div :if={!@loaded?} id="curriculum-loading" class="mt-16 text-center text-sm text-slate-500">
          Loading the curriculum map…
        </div>

        <div
          :if={@loaded? and @programs == []}
          class="mx-auto mt-16 max-w-lg rounded-lg border border-dashed border-slate-800 p-8 text-center text-sm text-slate-400"
        >
          The curriculum map follows an academic program's plan. Add the program and its semesters
          under Scheduling → Academic Programs, then come back.
        </div>

        <div
          :if={@loaded? and @programs != []}
          class="mx-auto w-full max-w-[2000px] flex-1 p-3 sm:p-4"
        >
          <CourseView.course_view
            :if={@live_action == :course}
            course_key={@course_key}
            courses={@courses}
            data={@data}
            nav={@nav}
            editor?={@curriculum_editor?}
          />
          <ThreadsView.threads
            :if={@live_action == :index and @tab == :threads}
            courses={@courses}
            data={@data}
            nav={@nav}
            filter={@threads_filter}
          />
          <AbetView.abet
            :if={@live_action == :index and @tab == :abet}
            courses={@courses}
            data={@data}
            nav={@nav}
            editor?={@curriculum_editor?}
            workbook={@abet_upload && @abet_upload.preview}
            upload={@curriculum_editor? && @uploads.abet_matrix}
          />
          <GraphView.graph
            :if={@live_action == :index and @tab == :graph}
            courses={@courses}
            data={@data}
            nav={@nav}
          />
          <SkillsView.skills
            :if={@live_action == :index and @tab == :skills}
            courses={@courses}
            data={@data}
            nav={@nav}
            editor?={@curriculum_editor?}
            editing_skill_id={@editing_skill_id}
          />
          <SuggestionsView.suggestions
            :if={@live_action == :index and @tab == :suggestions}
            courses={@courses}
            data={@data}
            nav={@nav}
            editor?={@curriculum_editor?}
            run_status={@run_status}
          />
        </div>
      </div>
    </Layouts.app>
    """
  end
end
