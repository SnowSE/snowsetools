defmodule SnowSeToolsWeb.Admin.SnowCacheComponent do
  use SnowSeToolsWeb, :live_component

  alias SnowSeTools.Snow.SnowCourseCacheDomainManager
  alias SnowSeToolsWeb.Admin.NewSemesterSyncComponent
  alias SnowSeToolsWeb.Admin.SyncedSemesterComponent

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

  # Only treat an empty term as a cancel when the user actually changed the
  # dropdown. Typing/pasting into the JWT field also fires phx-change, and the
  # dropdown reads "" whenever the selected term isn't listed in it (e.g. when
  # refreshing an already-cached semester).
  def handle_event(
        "select_sync_term",
        %{"_target" => ["snow_sync", "term_code"], "snow_sync" => %{"term_code" => ""}},
        socket
      ) do
    {:noreply, cancel_sync(socket)}
  end

  def handle_event(
        "select_sync_term",
        %{"snow_sync" => %{"term_code" => term_code} = attrs},
        socket
      ) do
    term_code = resolve_term_code(term_code, socket)
    jwt_token = String.trim(Map.get(attrs, "jwt_token", "") || "")

    {:noreply,
     socket
     |> assign(
       sync_term_code: term_code,
       sync_error: nil,
       sync_message: nil,
       jwt_token: jwt_token
     )
     |> put_sync_form()}
  end

  def handle_event("select_sync_term", %{"term_code" => term_code}, socket) do
    {:noreply,
     socket
     |> assign(
       sync_term_code: term_code,
       sync_error: nil,
       sync_message: nil,
       jwt_token: ""
     )
     |> put_sync_form()}
  end

  def handle_event("cancel_sync", _params, socket) do
    {:noreply, cancel_sync(socket)}
  end

  def handle_event("request_delete_term", %{"term_code" => term_code}, socket) do
    term = Enum.find(socket.assigns.terms, &(&1["term_code"] == term_code))

    pending_delete_term =
      if term do
        %{term_code: term["term_code"], label: term["term_name"]}
      else
        nil
      end

    {:noreply, assign(socket, :pending_delete_term, pending_delete_term)}
  end

  def handle_event("cancel_delete_term", _params, socket) do
    {:noreply, assign(socket, :pending_delete_term, nil)}
  end

  def handle_event("confirm_delete_term", _params, socket) do
    case socket.assigns.pending_delete_term do
      %{term_code: term_code, label: _label} ->
        SnowCourseCacheDomainManager.delete_term(pid: self(), term_code: term_code)

      _ ->
        :ok
    end

    {:noreply, assign(socket, :pending_delete_term, nil)}
  end

  def handle_event(
        "sync_classes_for_term",
        %{"snow_sync" => %{"term_code" => term_code} = attrs},
        socket
      ) do
    term_code = resolve_term_code(term_code, socket)
    jwt_token = String.trim(Map.get(attrs, "jwt_token", "") || "")

    if term_code in [nil, ""] do
      {:noreply, assign(socket, :sync_error, "Choose a semester before syncing.") |> put_sync_form()}
    else
      sync_classes(term_code, jwt_token, socket)
    end
  end

  defp sync_classes(term_code, jwt_token, socket) do
    if jwt_token == "" do
      {:noreply, assign(socket, :sync_error, "Paste your JWT before syncing.") |> put_sync_form()}
    else
      SnowCourseCacheDomainManager.sync_course_list(
        pid: self(),
        term_code: term_code,
        jwt_token: jwt_token
      )

      {:noreply,
       socket
       |> assign(:syncing, true)
       |> assign(:sync_error, nil)
       |> assign(:sync_message, nil)
       |> assign(:sync_term_code, nil)
       |> assign(:jwt_token, nil)
       |> put_sync_form()}
    end
  end

  def render(assigns) do
    ~H"""
    <section
      id={@id}
      class="rounded-xl border border-slate-800 bg-slate-900/70 p-5 shadow-xl shadow-slate-950/20"
    >
      <div class="mb-5">
        <h2 class="text-lg font-semibold text-slate-200">Cached Snow semesters</h2>
      </div>

      <.live_component
        module={NewSemesterSyncComponent}
        id="new-semester-sync"
        terms={@terms}
        sync_form={@sync_form}
        sync_term_code={@sync_term_code}
        jwt_token={@jwt_token}
        syncing={@syncing}
        target={@myself}
      />

      <%= if @sync_message do %>
        <div class="my-4 rounded-lg border border-emerald-500/20 bg-emerald-500/10 px-4 py-3 text-sm font-medium text-emerald-200">
          {@sync_message}
        </div>
      <% end %>

      <%= if @sync_error do %>
        <div class="my-4 rounded-lg border border-rose-500/20 bg-rose-500/10 px-4 py-3 text-sm font-medium text-rose-200">
          {@sync_error}
        </div>
      <% end %>

      <%= if @snapshot_error do %>
        <div class="my-4 rounded-lg border border-amber-500/20 bg-amber-500/10 px-4 py-3 text-sm font-medium text-amber-100">
          Unable to load cached semesters: {@snapshot_error}
        </div>
      <% end %>

      <%= if @terms == [] do %>
        <div class="pt-5 text-sm text-slate-500">
          No semesters cached yet.
        </div>
      <% else %>
        <div class="pt-2">
          <%= for term <- @terms do %>
            <.live_component
              module={SyncedSemesterComponent}
              id={"synced-semester-#{term["term_code"]}"}
              term={term}
              expanded?={@expanded_term_code == term["term_code"]}
              pending_delete_term={@pending_delete_term}
              target={@myself}
            />
          <% end %>
        </div>
      <% end %>

      <%= if @pending_delete_term do %>
        <.modal id="confirm-delete-term-modal" on_close="cancel_delete_term" target={@myself}>
          <div class="space-y-5">
            <div class="space-y-2">
              <h2 class="text-xl font-semibold text-slate-100">Delete semester</h2>
              <p class="text-sm leading-6 text-slate-300">
                Delete {@pending_delete_term.label} and all cached courses? This cannot be undone.
              </p>
            </div>

            <div class="flex justify-end gap-3">
              <button
                type="button"
                phx-click="cancel_delete_term"
                phx-target={@myself}
                class="rounded-xl border border-slate-700 px-4 py-2.5 text-sm font-semibold text-slate-300 transition hover:bg-slate-800"
              >
                Cancel
              </button>
              <button
                type="button"
                phx-click="confirm_delete_term"
                phx-target={@myself}
                class="rounded-xl bg-rose-500 px-4 py-2.5 text-sm font-semibold text-white transition hover:bg-rose-400"
              >
                Delete
              </button>
            </div>
          </div>
        </.modal>
      <% end %>
    </section>
    """
  end

  # Fall back to the term already selected (e.g. via "Refresh class list") when
  # the dropdown submits "" because that term isn't one of its options.
  defp resolve_term_code("", socket), do: socket.assigns[:sync_term_code]
  defp resolve_term_code(term_code, _socket), do: term_code

  defp base_assigns(socket) do
    socket
    |> assign_new(:terms, fn -> [] end)
    |> assign_new(:expanded_term_code, fn -> nil end)
    |> assign_new(:sync_term_code, fn -> nil end)
    |> assign_new(:sync_message, fn -> nil end)
    |> assign_new(:sync_error, fn -> nil end)
    |> assign_new(:jwt_token, fn -> nil end)
    |> assign_new(:snapshot_error, fn -> nil end)
    |> assign_new(:syncing, fn -> false end)
    |> assign_new(:pending_delete_term, fn -> nil end)
    |> put_sync_form()
  end

  defp apply_sync_result(socket, {:ok, message}) do
    socket
    |> assign(:sync_message, message)
    |> assign(:sync_error, nil)
    |> assign(:syncing, false)
    |> assign(:sync_term_code, nil)
    |> assign(:jwt_token, nil)
    |> put_sync_form()
  end

  defp apply_sync_result(socket, {:error, reason}) do
    assign(socket,
      sync_error: reason,
      sync_message: nil,
      syncing: false,
      jwt_token: nil
    )
    |> put_sync_form()
  end

  defp cancel_sync(socket) do
    assign(socket,
      sync_term_code: nil,
      sync_error: nil,
      syncing: false,
      jwt_token: nil
    )
    |> put_sync_form()
  end

  defp put_sync_form(socket) do
    assign(socket,
      sync_form:
        to_form(
          %{
            "term_code" => socket.assigns.sync_term_code || "",
            "jwt_token" => socket.assigns.jwt_token || ""
          },
          as: :snow_sync
        )
    )
  end
end
