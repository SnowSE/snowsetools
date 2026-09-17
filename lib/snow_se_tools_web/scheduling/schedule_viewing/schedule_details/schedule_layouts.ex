defmodule SnowSeToolsWeb.Scheduling.ScheduleLayouts do
  @moduledoc """
  Saving and reloading the schedule canvas: which people, rooms and program
  semesters are open, in what order, and which of them are grouped onto one
  week grid.

  A layout is view state, not data — it costs seconds to rebuild and nothing is
  destroyed when it is lost. So this never interrupts with a "you have unsaved
  changes" dialog. Instead the chip in the toolbar always says where you stand,
  the Save button's primary action names the outcome it will actually have, and
  switching layouts mid-edit offers an Undo afterwards rather than a
  confirmation beforehand.

  Editing a shared layout detaches it into an unsaved copy, so overwriting
  something other people load is never the default path.

  Layouts save to one of three places: this browser (`localStorage`, mirrored
  into the component by a hook), the signed-in user's account, or shared with
  everyone who has scheduling access.
  """

  use SnowSeToolsWeb, :html
  require Logger

  alias Phoenix.LiveView
  alias SnowSeToolsWeb.Scheduling.ScheduleLayoutsChrome, as: Chrome
  alias SnowSeTools.Scheduling.{ScheduleLayoutDomainManager, ScheduleLayoutPubSub}
  alias SnowSeToolsWeb.Scheduling.{ScheduleDetailsOrder, SchedulingLive, ScheduleViewer}

  defstruct [
    :server_layouts,
    :local_layouts,
    :loaded,
    :baseline,
    :undo,
    :dialog,
    :menu,
    :note,
    :pending_save,
    :pending_url_layout,
    :sources_ready
  ]

  @type loaded :: %{
          id: String.t(),
          name: String.t(),
          scope: String.t(),
          owner_email: String.t() | nil,
          can_edit?: boolean()
        }

  @type t :: %__MODULE__{
          server_layouts: [map()],
          local_layouts: [map()],
          loaded: loaded() | nil,
          baseline: [map()] | nil,
          undo: map() | nil,
          dialog: map() | nil,
          menu: :save | :load | nil,
          note: {:info | :warn | :error, String.t()} | nil,
          pending_save: {String.t(), String.t(), [map()]} | nil,
          pending_url_layout: String.t() | nil,
          sources_ready: MapSet.t(:server | :local)
        }

  @key :schedule_layouts
  @max_name_length Chrome.max_name_length()

  def assign_component(socket) do
    socket
    |> assign(@key, %__MODULE__{
      server_layouts: [],
      local_layouts: [],
      loaded: nil,
      baseline: nil,
      undo: nil,
      dialog: nil,
      menu: nil,
      note: nil,
      pending_save: nil,
      pending_url_layout: nil,
      sources_ready: MapSet.new()
    })
    |> maybe_attach_hooks()
    |> maybe_request_initial_data()
  end

  # -- Derived state ---------------------------------------------------------

  @doc """
  Has the canvas moved away from the layout that was loaded or last saved?

  Derived by comparing serialisations rather than tracked with a flag, so every
  way of changing the canvas — closing a card, grouping, dragging, resizing —
  counts without each event having to remember to say so.
  """
  def dirty?(%__MODULE__{baseline: nil}, _schedule_details_order), do: false

  def dirty?(%__MODULE__{baseline: baseline}, schedule_details_order),
    do: ScheduleDetailsOrder.to_layout_entries(schedule_details_order) != baseline

  @doc "A loaded shared layout that has been edited is now an unsaved copy."
  def detached?(%__MODULE__{loaded: %{scope: "shared"}} = state, schedule_details_order),
    do: dirty?(state, schedule_details_order)

  def detached?(%__MODULE__{}, _schedule_details_order), do: false

  def all_layouts(%__MODULE__{} = state), do: state.local_layouts ++ state.server_layouts

  @doc "The name of the layout on screen, for the page URL. Nil when none is loaded."
  def loaded_name(%__MODULE__{loaded: %{name: name}}), do: name
  def loaded_name(%__MODULE__{}), do: nil

  # -- Render ----------------------------------------------------------------

  attr :state, __MODULE__, required: true
  attr :schedule_details_order, :any, required: true
  attr :editor?, :boolean, required: true
  slot :leading, doc: "Controls shown at the start of the layout toolbar row."

  def render(assigns) do
    state = assigns.state
    entries = ScheduleDetailsOrder.to_layout_entries(assigns.schedule_details_order)
    layouts = all_layouts(state)

    assigns =
      assigns
      |> assign(:empty?, entries == [])
      |> assign(:dirty?, dirty?(state, assigns.schedule_details_order))
      |> assign(:detached?, detached?(state, assigns.schedule_details_order))
      |> assign(:any_layouts?, layouts != [])
      |> assign(:scope_groups, Chrome.scope_groups(layouts))
      |> assign(
        :show_undo?,
        state.undo != nil and not dirty?(state, assigns.schedule_details_order)
      )
      |> assign(:primary, primary_action(state, assigns.schedule_details_order, entries))

    ~H"""
    <div
      id="schedule-layouts"
      phx-hook=".ScheduleLayoutsStore"
      phx-click-away={@state.menu && "schedule-layouts:close_menus"}
      class="mb-2 flex w-full flex-col gap-2"
    >
      <div class="flex flex-wrap items-center justify-end gap-2">
        {render_slot(@leading)}

        <Chrome.loaded_chip
          :if={@state.loaded}
          loaded={@state.loaded}
          dirty?={@dirty?}
          detached?={@detached?}
        />

        <div class="relative flex">
          <button
            type="button"
            id="schedule-layouts-save"
            phx-click="schedule-layouts:primary_save"
            disabled={@primary.action == :none}
            class={[
              "inline-flex h-7 items-center gap-1.5 rounded-l-md border border-indigo-400/60",
              "bg-indigo-500/15 px-2.5 text-xs font-medium text-indigo-200 transition-colors",
              "enabled:hover:bg-indigo-500/25 enabled:hover:text-indigo-100",
              "disabled:cursor-not-allowed disabled:opacity-40"
            ]}
          >
            <.icon name="hero-bookmark-square" class="size-3.5" />
            {@primary.label}
          </button>
          <button
            type="button"
            id="schedule-layouts-save-menu"
            phx-click="schedule-layouts:toggle_save_menu"
            aria-label="More layout options"
            aria-expanded={to_string(@state.menu == :save)}
            class={[
              "-ml-px inline-flex h-7 items-center justify-center rounded-r-md border",
              "border-indigo-400/60 bg-indigo-500/15 px-1.5 text-indigo-200 transition-colors",
              "hover:bg-indigo-500/25 hover:text-indigo-100"
            ]}
          >
            <.icon name="hero-chevron-down" class="size-3.5" />
          </button>

          <div
            :if={@state.menu == :save}
            class="absolute right-0 top-full z-40 mt-1 w-64 rounded-lg border border-slate-700 bg-slate-950 p-1 shadow-2xl shadow-black/70"
          >
            <Chrome.menu_header :if={@state.loaded && @state.loaded.scope == "shared"}>
              Shared · saved by {@state.loaded.owner_email || "someone else"}
            </Chrome.menu_header>

            <Chrome.menu_button
              :if={@state.loaded && @state.loaded.scope == "shared"}
              event="schedule-layouts:open_save_dialog"
              mode="copy"
              icon="hero-document-duplicate"
            >
              Save as my copy…
            </Chrome.menu_button>

            <Chrome.menu_button
              :if={@state.loaded && @state.loaded.scope == "shared" && @state.loaded.can_edit?}
              event="schedule-layouts:update_loaded"
              icon="hero-globe-alt"
              disabled={!@dirty?}
            >
              Update the shared layout
            </Chrome.menu_button>

            <div
              :if={@state.loaded && @state.loaded.scope == "shared"}
              class="my-1 h-px bg-slate-800"
            />

            <Chrome.menu_button
              event="schedule-layouts:open_save_dialog"
              mode="new"
              icon="hero-plus"
              disabled={@empty?}
            >
              Save as new…
            </Chrome.menu_button>

            <Chrome.menu_button
              :if={@state.loaded && @state.loaded.scope != "shared" && @state.loaded.can_edit?}
              event="schedule-layouts:update_loaded"
              icon="hero-arrow-down-on-square"
              disabled={!@dirty?}
            >
              Update “{truncate(@state.loaded.name, 22)}”
            </Chrome.menu_button>

            <Chrome.menu_button
              :if={@state.loaded && @state.loaded.can_edit?}
              event="schedule-layouts:open_save_dialog"
              mode="rename"
              icon="hero-pencil"
            >
              Rename…
            </Chrome.menu_button>

            <Chrome.menu_button
              :if={@state.loaded && @state.loaded.scope == "local"}
              event="schedule-layouts:promote_local"
              icon="hero-cloud-arrow-up"
            >
              Move to my account
            </Chrome.menu_button>

            <div :if={@state.loaded && @state.loaded.can_edit?} class="my-1 h-px bg-slate-800" />

            <Chrome.menu_button
              :if={@state.loaded && @state.loaded.can_edit?}
              event="schedule-layouts:delete_loaded"
              icon="hero-trash"
              danger
            >
              Delete “{truncate(@state.loaded.name, 22)}”
            </Chrome.menu_button>
          </div>
        </div>

        <div :if={@any_layouts?} class="relative flex">
          <button
            type="button"
            id="schedule-layouts-load"
            phx-click="schedule-layouts:toggle_load_menu"
            aria-expanded={to_string(@state.menu == :load)}
            class="inline-flex h-7 items-center gap-1.5 rounded-md border border-slate-700 px-2.5 text-xs font-medium text-slate-300 transition-colors hover:bg-slate-800 hover:text-slate-100"
          >
            <.icon name="hero-arrow-down-tray" class="size-3.5" /> Load Layout
            <.icon name="hero-chevron-down" class="size-3" />
          </button>

          <div
            :if={@state.menu == :load}
            class="absolute right-0 top-full z-40 mt-1 max-h-96 w-80 overflow-y-auto rounded-lg border border-slate-700 bg-slate-950 p-1 shadow-2xl shadow-black/70"
          >
            <div :for={group <- @scope_groups}>
              <Chrome.menu_header>{group.label}</Chrome.menu_header>
              <Chrome.layout_row
                :for={layout <- group.layouts}
                layout={layout}
                current?={@state.loaded != nil && @state.loaded.id == layout["id"]}
              />
            </div>
          </div>
        </div>
      </div>

      <Chrome.note :if={@state.note} note={@state.note} />
    </div>

    <Chrome.undo_toast :if={@show_undo?} undo={@state.undo} />
    <Chrome.save_dialog :if={@state.dialog} dialog={@state.dialog} editor?={@editor?} />

    <script :type={Phoenix.LiveView.ColocatedHook} name=".ScheduleLayoutsStore">
      // Browser-scoped layouts never reach the server, so the component holds a
      // mirror of them and this hook is the only thing that touches the store.
      const STORAGE_KEY = "scheduling:layouts";

      export default {
        mounted() {
          this.sync();

          this.handleEvent("schedule-layouts:write_local", ({ layout }) => {
            const kept = this.read().filter((saved) => saved.id !== layout.id);
            this.write([...kept, layout]);
          });

          this.handleEvent("schedule-layouts:delete_local", ({ id }) => {
            this.write(this.read().filter((saved) => saved.id !== id));
          });
        },

        read() {
          try {
            const raw = window.localStorage.getItem(STORAGE_KEY);
            const parsed = raw ? JSON.parse(raw) : [];
            return Array.isArray(parsed) ? parsed : [];
          } catch (error) {
            console.error("Could not read layouts saved in this browser", error);
            this.pushEvent("schedule-layouts:local_store_failed", { reason: String(error) });
            return [];
          }
        },

        write(layouts) {
          try {
            window.localStorage.setItem(STORAGE_KEY, JSON.stringify(layouts));
          } catch (error) {
            console.error("Could not save the layout in this browser", error);
            this.pushEvent("schedule-layouts:local_store_failed", { reason: String(error) });
            return;
          }

          this.sync();
        },

        sync() {
          this.pushEvent("schedule-layouts:local_synced", { layouts: this.read() });
        }
      }
    </script>
    """
  end

  # -- The layout in the URL -------------------------------------------------

  @doc """
  Reads the layout named in the page URL.

  Never reloads the layout already on screen: the URL is patched for other
  reasons too, and re-applying would throw away edits in progress.
  """
  def hooked_params(params, _uri, socket) do
    requested = params["layout"]

    socket =
      if is_binary(requested) and requested != "" and
           !matches_loaded?(socket.assigns[@key], requested) do
        socket
        |> put_state(%{pending_url_layout: requested})
        |> maybe_apply_pending_layout()
      else
        socket
      end

    {:cont, socket}
  end

  @doc """
  Applies a layout named in the URL once everything it needs has arrived: the
  saved layouts, a selected term, and that term's owner metadata. Called again
  as each of those lands, because they arrive in any order.
  """
  def maybe_apply_pending_layout(socket) do
    state = socket.assigns[@key]

    if is_binary(state.pending_url_layout) and term_ready?(socket) do
      apply_pending_layout(socket, state, resolve_layout(state, state.pending_url_layout))
    else
      socket
    end
  end

  defp apply_pending_layout(socket, _state, layout) when is_map(layout) do
    socket
    |> put_state(%{pending_url_layout: nil})
    |> load_layout(layout)
  end

  defp apply_pending_layout(socket, state, nil) do
    # Server-backed and browser-local layouts arrive independently, so a name is
    # only genuinely missing once both sources have reported.
    if MapSet.size(state.sources_ready) < 2 do
      socket
    else
      Logger.info("No saved layout matched #{inspect(state.pending_url_layout)} from the URL")

      put_state(socket, %{
        pending_url_layout: nil,
        note:
          {:warn,
           "No saved layout called “#{state.pending_url_layout}”. It may have been renamed, deleted, or saved to someone else's browser."}
      })
    end
  end

  defp term_ready?(socket) do
    viewer_state = socket.assigns.schedule_viewer_state

    is_binary(viewer_state.selected_term_code) and
      ScheduleViewer.available_owner_keys(viewer_state) != nil
  end

  # A URL may carry the layout's name or its id. Ids match exactly; names match
  # case-insensitively, preferring your own layouts, then shared ones, then this
  # browser's — so a link someone sends resolves to the shared layout for them
  # even when they happen to have a private one by the same name.
  defp resolve_layout(%__MODULE__{} = state, param) do
    layouts = all_layouts(state)

    Enum.find(layouts, &(&1["id"] == param)) ||
      Enum.find_value(["user", "shared", "local"], &find_by_name(layouts, param, &1))
  end

  defp find_by_name(layouts, name, scope) do
    Enum.find(layouts, fn layout ->
      layout["scope"] == scope and String.downcase(layout["name"]) == String.downcase(name)
    end)
  end

  defp matches_loaded?(%__MODULE__{loaded: nil}, _param), do: false

  defp matches_loaded?(%__MODULE__{loaded: loaded}, param) do
    loaded.id == param or String.downcase(loaded.name) == String.downcase(param)
  end

  # Keeps the URL naming the layout on screen so the page can be bookmarked.
  defp sync_url(socket) do
    LiveView.push_patch(socket,
      to:
        SchedulingLive.scheduling_path(
          mode: socket.assigns.mode,
          term: socket.assigns.schedule_viewer_state.selected_term_code,
          layout: loaded_name(socket.assigns[@key])
        ),
      replace: true
    )
  end

  # -- Events ----------------------------------------------------------------

  def hooked_event("schedule-layouts:toggle_save_menu", _params, socket),
    do: {:halt, toggle_menu(socket, :save)}

  def hooked_event("schedule-layouts:toggle_load_menu", _params, socket),
    do: {:halt, toggle_menu(socket, :load)}

  def hooked_event("schedule-layouts:close_menus", _params, socket),
    do: {:halt, put_state(socket, %{menu: nil})}

  def hooked_event("schedule-layouts:dismiss_note", _params, socket),
    do: {:halt, put_state(socket, %{note: nil})}

  def hooked_event("schedule-layouts:dismiss_undo", _params, socket),
    do: {:halt, put_state(socket, %{undo: nil})}

  def hooked_event("schedule-layouts:primary_save", _params, socket) do
    state = socket.assigns[@key]
    order_state = socket.assigns.schedule_details_order
    entries = ScheduleDetailsOrder.to_layout_entries(order_state)

    case primary_action(state, order_state, entries).action do
      :save_new -> {:halt, open_dialog(socket, "new")}
      :save_copy -> {:halt, open_dialog(socket, "copy")}
      :update -> {:halt, update_loaded(socket)}
      :none -> {:halt, socket}
    end
  end

  def hooked_event("schedule-layouts:open_save_dialog", %{"mode" => mode}, socket)
      when mode in ["new", "copy", "rename"] do
    {:halt, open_dialog(socket, mode)}
  end

  def hooked_event("schedule-layouts:close_dialog", _params, socket),
    do: {:halt, put_state(socket, %{dialog: nil})}

  def hooked_event("schedule-layouts:update_loaded", _params, socket),
    do: {:halt, update_loaded(socket)}

  def hooked_event("schedule-layouts:suggest_again", _params, socket) do
    state = socket.assigns[@key]

    case state.dialog do
      %{suggestions: [_first | _rest] = suggestions, suggestion_index: index} = dialog ->
        next_index = rem(index + 1, length(suggestions))

        {:halt,
         put_state(socket, %{
           dialog: %{
             dialog
             | name: Enum.at(suggestions, next_index),
               suggestion_index: next_index,
               name_touched?: false,
               collision: nil
           }
         })}

      _no_suggestions ->
        {:halt, socket}
    end
  end

  def hooked_event("schedule-layouts:dialog_change", params, socket) do
    case socket.assigns[@key].dialog do
      nil ->
        {:halt, socket}

      dialog ->
        name = params["name"] || dialog.name

        {:halt,
         put_state(socket, %{
           dialog: %{
             dialog
             | name: name,
               name_touched?: dialog.name_touched? or name != dialog.name,
               scope: params["scope"] || dialog.scope,
               collision: collision_after_change(dialog, params, name)
           }
         })}
    end
  end

  def hooked_event("schedule-layouts:save", params, socket) do
    case socket.assigns[@key].dialog do
      nil ->
        Logger.warning("Ignored a layout save with no dialog open")
        {:halt, socket}

      dialog ->
        name = params["name"] || dialog.name

        dialog = %{
          dialog
          | name: String.trim(name),
            scope: params["scope"] || dialog.scope,
            collision: collision_after_change(dialog, params, name)
        }

        {:halt, commit_save(socket, dialog)}
    end
  end

  def hooked_event("schedule-layouts:load", %{"id" => layout_id}, socket) do
    state = socket.assigns[@key]

    case Enum.find(all_layouts(state), &(&1["id"] == layout_id)) do
      nil ->
        Logger.warning("Ignored a load of missing layout #{inspect(layout_id)}")

        {:halt,
         put_state(socket, %{menu: nil, note: {:error, "That layout is no longer available."}})}

      layout ->
        {:halt, load_layout(socket, layout)}
    end
  end

  def hooked_event("schedule-layouts:undo_load", _params, socket) do
    case socket.assigns[@key].undo do
      nil ->
        {:halt, socket}

      undo ->
        {socket, _outcome} =
          ScheduleDetailsOrder.apply_layout_entries(socket,
            entries: undo.entries,
            available_owner_keys: nil
          )

        {:halt,
         socket
         |> put_state(%{
           loaded: undo.loaded,
           baseline: undo.baseline,
           undo: nil,
           menu: nil,
           note: nil
         })
         |> sync_url()}
    end
  end

  def hooked_event("schedule-layouts:delete_loaded", _params, socket) do
    state = socket.assigns[@key]

    case state.loaded do
      nil ->
        {:halt, socket}

      %{can_edit?: false} = loaded ->
        Logger.warning("Refused in-page delete of layout #{loaded.id} the user cannot edit")
        {:halt, put_state(socket, %{menu: nil, note: {:error, "You can't delete that layout."}})}

      %{scope: "local"} = loaded ->
        {:halt,
         socket
         |> LiveView.push_event("schedule-layouts:delete_local", %{id: loaded.id})
         |> put_state(%{
           loaded: nil,
           baseline: nil,
           menu: nil,
           note: {:info, "Deleted “#{loaded.name}” from this browser."}
         })
         |> sync_url()}

      loaded ->
        ScheduleLayoutDomainManager.delete_layout(
          pid: self(),
          user: socket.assigns.current_user,
          layout_id: loaded.id
        )

        {:halt, put_state(socket, %{menu: nil})}
    end
  end

  def hooked_event("schedule-layouts:promote_local", _params, socket) do
    state = socket.assigns[@key]

    loaded = state.loaded
    layout = loaded && Enum.find(state.local_layouts, &(&1["id"] == loaded.id))

    cond do
      !match?(%{scope: "local"}, loaded) ->
        {:halt, socket}

      is_nil(layout) ->
        Logger.warning("Could not move a local layout that is no longer in browser storage")

        {:halt,
         put_state(socket, %{
           menu: nil,
           note: {:error, "That layout is no longer in this browser."}
         })}

      true ->
        ScheduleLayoutDomainManager.save_layout(
          pid: self(),
          user: socket.assigns.current_user,
          attrs: %{
            name: layout["name"],
            scope: "user",
            term_code: layout["term_code"],
            entries: layout["entries"]
          }
        )

        {:halt,
         socket
         |> LiveView.push_event("schedule-layouts:delete_local", %{id: loaded.id})
         |> put_state(%{menu: nil, pending_save: {layout["name"], "user", layout["entries"]}})}
    end
  end

  def hooked_event("schedule-layouts:local_synced", %{"layouts" => layouts}, socket)
      when is_list(layouts) do
    local_layouts =
      layouts
      |> Enum.filter(&valid_local_layout?/1)
      |> Enum.map(&Map.merge(&1, %{"scope" => "local", "can_edit" => true}))
      |> Enum.sort_by(&String.downcase(&1["name"]))

    {:halt,
     socket
     |> put_state(%{
       local_layouts: local_layouts,
       sources_ready: MapSet.put(socket.assigns[@key].sources_ready, :local)
     })
     |> maybe_apply_pending_layout()}
  end

  def hooked_event("schedule-layouts:local_store_failed", %{"reason" => reason}, socket) do
    Logger.error("Browser layout storage failed: #{inspect(reason)}")

    {:halt,
     put_state(socket, %{
       note:
         {:error,
          "This browser wouldn't store the layout. Save it to your account instead, or leave private browsing."}
     })}
  end

  def hooked_event(_event, _params, socket), do: {:cont, socket}

  # -- Messages --------------------------------------------------------------

  def hooked_info({:schedule_layouts, {:layouts_listed, layouts}}, socket) do
    {:halt,
     socket
     |> put_state(%{
       server_layouts: Enum.map(layouts, &decorate(&1, socket)),
       sources_ready: MapSet.put(socket.assigns[@key].sources_ready, :server)
     })
     |> maybe_apply_pending_layout()}
  end

  def hooked_info({:schedule_layouts, {:layout_saved, layout}}, socket) do
    state = socket.assigns[@key]
    layout = decorate(layout, socket)
    server_layouts = merge_layout(state.server_layouts, layout)

    # The same event arrives twice: once addressed to whoever asked for the save,
    # and once by broadcast to every other open page. Only the session that asked
    # adopts it as the layout being worked in. The baseline comes from the
    # entries that were actually written, not from whatever is on screen now, so
    # an edit made while the write was in flight still reads as edited.
    saved_name = layout["name"]
    saved_scope = layout["scope"]

    case state.pending_save do
      {^saved_name, ^saved_scope, saved_entries} ->
        {:halt,
         socket
         |> put_state(%{
           server_layouts: server_layouts,
           pending_save: nil,
           loaded: to_loaded(layout),
           baseline: saved_entries,
           note: {:info, "Saved “#{saved_name}” to #{Chrome.scope_style(saved_scope).label}."}
         })
         |> sync_url()}

      _not_ours ->
        {:halt, put_state(socket, %{server_layouts: server_layouts})}
    end
  end

  def hooked_info({:schedule_layouts, {:layout_deleted, %{id: layout_id}}}, socket),
    do: {:halt, drop_layout(socket, layout_id)}

  def hooked_info({:schedule_layouts, {:layout_deleted, layout_id}}, socket)
      when is_binary(layout_id),
      do: {:halt, drop_layout(socket, layout_id)}

  def hooked_info({:schedule_layouts, {:layouts_error, reason}}, socket) do
    Logger.error("Could not list saved layouts: #{inspect(reason)}")

    {:halt,
     put_state(socket, %{note: {:error, "Couldn't load your saved layouts. #{describe(reason)}"}})}
  end

  def hooked_info({:schedule_layouts, {:layout_error, reason}}, socket) do
    Logger.error("Saved layout operation failed: #{inspect(reason)}")

    {:halt,
     put_state(socket, %{
       dialog: nil,
       pending_save: nil,
       note: {:error, "Couldn't save that layout. #{describe(reason)}"}
     })}
  end

  def hooked_info({:schedule_layouts, {:name_suggested, request_ref, names}}, socket) do
    case socket.assigns[@key].dialog do
      %{request_ref: ^request_ref} = dialog ->
        # The field is only overwritten while the person has left it alone.
        dialog =
          if dialog.name_touched? do
            %{dialog | suggesting?: false, suggestions: names, suggestion_index: 0}
          else
            %{
              dialog
              | suggesting?: false,
                suggestions: names,
                suggestion_index: 0,
                name: List.first(names) || dialog.name,
                collision: nil
            }
          end

        {:halt, put_state(socket, %{dialog: dialog})}

      _stale_or_closed ->
        {:halt, socket}
    end
  end

  def hooked_info({:schedule_layouts, {:name_suggestion_failed, request_ref, _reason}}, socket) do
    case socket.assigns[@key].dialog do
      %{request_ref: ^request_ref} = dialog ->
        {:halt,
         put_state(socket, %{dialog: %{dialog | suggesting?: false, suggestion_failed?: true}})}

      _stale_or_closed ->
        {:halt, socket}
    end
  end

  def hooked_info(_message, socket), do: {:cont, socket}

  # -- Actions ---------------------------------------------------------------

  defp primary_action(%__MODULE__{} = state, schedule_details_order, entries) do
    cond do
      is_nil(state.loaded) and entries == [] -> %{action: :none, label: "Save Layout"}
      is_nil(state.loaded) -> %{action: :save_new, label: "Save Layout"}
      state.loaded.scope == "shared" -> %{action: :save_copy, label: "Save as my copy"}
      !state.loaded.can_edit? -> %{action: :save_copy, label: "Save as my copy"}
      !dirty?(state, schedule_details_order) -> %{action: :none, label: "Saved"}
      true -> %{action: :update, label: "Update “#{truncate(state.loaded.name, 18)}”"}
    end
  end

  defp open_dialog(socket, mode) do
    state = socket.assigns[@key]
    order_state = socket.assigns.schedule_details_order
    term_name = ScheduleViewer.selected_term_name(socket.assigns.schedule_viewer_state)
    request_ref = random_ref()

    # The dialog opens on a name it already has. The model's suggestion is an
    # improvement that arrives later, never something the save waits on.
    if mode == "new" do
      ScheduleLayoutDomainManager.suggest_name(
        pid: self(),
        request_ref: request_ref,
        card_labels: ScheduleDetailsOrder.card_labels(order_state, socket.assigns.week_schedules),
        term_name: term_name
      )
    end

    put_state(socket, %{
      menu: nil,
      note: nil,
      dialog: %{
        mode: mode,
        name: initial_dialog_name(mode, state, order_state, term_name),
        name_touched?: mode != "new",
        scope: initial_dialog_scope(mode, state),
        suggesting?: mode == "new",
        suggestion_failed?: false,
        suggestions: [],
        suggestion_index: 0,
        request_ref: request_ref,
        collision: nil
      }
    })
  end

  defp initial_dialog_name("copy", %__MODULE__{loaded: %{name: name}}, _order, _term),
    do: truncate("Copy of #{name}", @max_name_length)

  defp initial_dialog_name("rename", %__MODULE__{loaded: %{name: name}}, _order, _term), do: name

  defp initial_dialog_name(_mode, _state, order_state, term_name),
    do: local_name(order_state, term_name)

  defp initial_dialog_scope("rename", %__MODULE__{loaded: %{scope: scope}}), do: scope
  defp initial_dialog_scope("copy", %__MODULE__{}), do: "user"
  defp initial_dialog_scope(_mode, %__MODULE__{loaded: %{scope: "shared"}}), do: "user"
  defp initial_dialog_scope(_mode, %__MODULE__{loaded: %{scope: scope}}), do: scope
  defp initial_dialog_scope(_mode, %__MODULE__{}), do: "local"

  # A name built from what is on screen. Always available, never blocking, and
  # the value that ships when the model is unreachable or mocked out in tests.
  defp local_name(order_state, term_name) do
    counts =
      order_state
      |> ScheduleDetailsOrder.to_layout_entries()
      |> Enum.flat_map(fn
        %{"kind" => "overlay", "members" => members} -> members
        %{"key" => key} -> [key]
      end)
      |> Enum.frequencies_by(&owner_kind/1)

    parts =
      [
        pluralise(counts[:professor], "person", "people"),
        pluralise(counts[:room], "room", "rooms"),
        pluralise(counts[:academic_program_semester], "program semester", "program semesters")
      ]
      |> Enum.reject(&is_nil/1)

    case {parts, term_name} do
      {[], nil} -> "Empty layout"
      {[], term} -> "Empty layout · #{term}"
      {parts, nil} -> Enum.join(parts, " · ")
      {parts, term} -> truncate(Enum.join(parts, " · ") <> " · #{term}", @max_name_length)
    end
  end

  defp pluralise(nil, _singular, _plural), do: nil
  defp pluralise(0, _singular, _plural), do: nil
  defp pluralise(1, singular, _plural), do: "1 #{singular}"
  defp pluralise(count, _singular, plural), do: "#{count} #{plural}"

  defp owner_kind("professor:" <> _rest), do: :professor
  defp owner_kind("room:" <> _rest), do: :room
  defp owner_kind("academic_program_semester:" <> _rest), do: :academic_program_semester
  defp owner_kind(_key), do: :other

  defp collision_after_change(dialog, params, name) do
    cond do
      params["scope"] not in [nil, dialog.scope] ->
        nil

      is_binary(params["collision"]) and dialog.collision != nil ->
        %{dialog.collision | choice: params["collision"]}

      dialog.collision == nil ->
        nil

      String.trim(name) != String.trim(dialog.name) ->
        nil

      true ->
        dialog.collision
    end
  end

  defp commit_save(socket, dialog) do
    if dialog.scope == "shared" and not editor?(socket) do
      Logger.info("Refused a shared layout save for a view-only user")

      LiveView.put_flash(
        socket,
        :error,
        "Only schedule editors can share a layout with everyone."
      )
    else
      write_save(socket, dialog)
    end
  end

  # A missing flag means the page never declared one, so treat it as view-only.
  defp editor?(socket), do: socket.assigns[:scheduling_editor?] == true

  defp write_save(socket, dialog) do
    state = socket.assigns[@key]
    name = String.trim(dialog.name)

    clash =
      find_clash(state, name: name, scope: dialog.scope, ignore_loaded?: dialog.mode == "rename")

    cond do
      name == "" ->
        socket

      clash != nil and is_nil(dialog.collision) ->
        put_state(socket, %{dialog: %{dialog | collision: %{choice: "replace"}}})

      clash != nil and dialog.collision.choice == "replace" ->
        write_existing(socket, clash, dialog: dialog, name: name)

      true ->
        name = if clash, do: unique_copy_name(state, name, dialog.scope), else: name
        write_new(socket, dialog, name: name)
    end
  end

  defp find_clash(state, name: name, scope: scope, ignore_loaded?: ignore_loaded?) do
    ignored_id = if ignore_loaded? and state.loaded, do: state.loaded.id

    Enum.find(all_layouts(state), fn layout ->
      layout["scope"] == scope and
        layout["id"] != ignored_id and
        String.downcase(layout["name"]) == String.downcase(name)
    end)
  end

  defp unique_copy_name(state, name, scope) do
    Enum.find_value(2..50, "#{name} (copy)", fn suffix ->
      candidate = truncate("#{name} (#{suffix})", @max_name_length)

      if find_clash(state, name: candidate, scope: scope, ignore_loaded?: false) == nil do
        candidate
      end
    end)
  end

  # A rename keeps the layout's contents; every other mode writes the canvas.
  defp write_existing(socket, layout, dialog: dialog, name: name) do
    entries =
      if dialog.mode == "rename" do
        layout["entries"]
      else
        ScheduleDetailsOrder.to_layout_entries(socket.assigns.schedule_details_order)
      end

    cond do
      layout["scope"] == "local" and dialog.scope == "local" ->
        write_local(socket, %{layout | "name" => name, "entries" => entries})

      layout["scope"] == "local" ->
        # Moving out of the browser: create it on the server, drop the local copy.
        socket
        |> LiveView.push_event("schedule-layouts:delete_local", %{id: layout["id"]})
        |> create_on_server(name: name, scope: dialog.scope, entries: entries)

      dialog.scope == "local" ->
        # Moving into the browser: the server copy is deliberately left alone.
        write_local(socket, new_local_layout(socket, name: name, entries: entries))

      true ->
        ScheduleLayoutDomainManager.update_layout(
          pid: self(),
          user: socket.assigns.current_user,
          layout_id: layout["id"],
          attrs: %{name: name, scope: dialog.scope, entries: entries}
        )

        put_state(socket, %{dialog: nil, pending_save: {name, dialog.scope, entries}})
    end
  end

  defp write_new(socket, dialog, name: name) do
    entries = ScheduleDetailsOrder.to_layout_entries(socket.assigns.schedule_details_order)

    if dialog.scope == "local" do
      write_local(socket, new_local_layout(socket, name: name, entries: entries))
    else
      create_on_server(socket, name: name, scope: dialog.scope, entries: entries)
    end
  end

  defp create_on_server(socket, name: name, scope: scope, entries: entries) do
    ScheduleLayoutDomainManager.save_layout(
      pid: self(),
      user: socket.assigns.current_user,
      attrs: %{
        name: name,
        scope: scope,
        term_code: socket.assigns.schedule_viewer_state.selected_term_code,
        entries: entries
      }
    )

    put_state(socket, %{dialog: nil, pending_save: {name, scope, entries}})
  end

  defp new_local_layout(socket, name: name, entries: entries) do
    %{
      "id" => "local-" <> random_ref(),
      "name" => name,
      "scope" => "local",
      "can_edit" => true,
      "owner_email" => nil,
      "term_code" => socket.assigns.schedule_viewer_state.selected_term_code,
      "entries" => entries,
      "updated_at" => DateTime.utc_now() |> DateTime.to_iso8601()
    }
  end

  defp write_local(socket, layout) do
    socket
    |> LiveView.push_event("schedule-layouts:write_local", %{layout: layout})
    |> put_state(%{
      dialog: nil,
      menu: nil,
      pending_save: nil,
      loaded: to_loaded(layout),
      baseline: ScheduleDetailsOrder.to_layout_entries(socket.assigns.schedule_details_order),
      local_layouts: merge_layout(socket.assigns[@key].local_layouts, layout),
      note: {:info, "Saved “#{layout["name"]}” in this browser."}
    })
    |> sync_url()
  end

  defp update_loaded(socket) do
    state = socket.assigns[@key]

    case state.loaded do
      nil ->
        socket

      %{can_edit?: false} = loaded ->
        Logger.warning("Refused in-page update of layout #{loaded.id} the user cannot edit")
        put_state(socket, %{menu: nil, note: {:error, "You can't change that layout."}})

      loaded ->
        entries = ScheduleDetailsOrder.to_layout_entries(socket.assigns.schedule_details_order)

        case Enum.find(all_layouts(state), &(&1["id"] == loaded.id)) do
          nil ->
            Logger.warning("Could not update layout #{loaded.id}, which is no longer listed")
            put_state(socket, %{menu: nil, note: {:error, "That layout is no longer available."}})

          %{"scope" => "local"} = layout ->
            write_local(socket, %{layout | "entries" => entries})

          _server_layout ->
            ScheduleLayoutDomainManager.update_layout(
              pid: self(),
              user: socket.assigns.current_user,
              layout_id: loaded.id,
              attrs: %{name: nil, scope: nil, entries: entries}
            )

            put_state(socket, %{menu: nil, pending_save: {loaded.name, loaded.scope, entries}})
        end
    end
  end

  defp load_layout(socket, layout) do
    state = socket.assigns[@key]
    order_state = socket.assigns.schedule_details_order

    undo =
      if dirty?(state, order_state) do
        %{
          entries: ScheduleDetailsOrder.to_layout_entries(order_state),
          loaded: state.loaded,
          baseline: state.baseline,
          message: "Replaced your unsaved layout."
        }
      end

    {socket, outcome} =
      ScheduleDetailsOrder.apply_layout_entries(socket,
        entries: layout["entries"] || [],
        available_owner_keys:
          ScheduleViewer.available_owner_keys(socket.assigns.schedule_viewer_state)
      )

    socket
    |> put_state(%{
      menu: nil,
      undo: undo,
      loaded: to_loaded(layout),
      # Re-read what actually landed, so a layout that loaded partially does not
      # immediately read as edited.
      baseline: ScheduleDetailsOrder.to_layout_entries(socket.assigns.schedule_details_order),
      note: load_note(layout, outcome)
    })
    |> sync_url()
  end

  defp load_note(_layout, %{missing: []}), do: nil

  defp load_note(layout, %{applied: applied, missing: missing}) do
    total = applied + length(missing)
    names = Enum.map_join(Enum.take(missing, 3), ", ", &owner_display_name/1)
    remainder = if length(missing) > 3, do: " and #{length(missing) - 3} more", else: ""
    verb = if length(missing) == 1, do: "isn't", else: "aren't"

    {:warn,
     "Loaded #{applied} of #{total} cards from “#{layout["name"]}” — " <>
       "#{names}#{remainder} #{verb} in this term."}
  end

  defp owner_display_name(owner_key),
    do: owner_key |> String.split(":", parts: 2) |> List.last()

  # -- State plumbing --------------------------------------------------------

  defp toggle_menu(socket, menu) do
    current = socket.assigns[@key].menu
    put_state(socket, %{menu: if(current == menu, do: nil, else: menu)})
  end

  defp put_state(socket, changes),
    do: assign(socket, @key, struct(socket.assigns[@key], changes))

  defp to_loaded(layout) do
    %{
      id: layout["id"],
      name: layout["name"],
      scope: layout["scope"],
      owner_email: layout["owner_email"],
      can_edit?: layout["can_edit"] != false
    }
  end

  defp merge_layout(layouts, layout) do
    layouts =
      if Enum.any?(layouts, &(&1["id"] == layout["id"])) do
        Enum.map(layouts, fn existing ->
          if existing["id"] == layout["id"], do: layout, else: existing
        end)
      else
        layouts ++ [layout]
      end

    Enum.sort_by(layouts, &String.downcase(&1["name"] || ""))
  end

  defp drop_layout(socket, layout_id) do
    state = socket.assigns[@key]
    remaining = Enum.reject(state.server_layouts, &(&1["id"] == layout_id))

    if state.loaded && state.loaded.id == layout_id do
      socket
      |> put_state(%{
        server_layouts: remaining,
        loaded: nil,
        baseline: nil,
        note: {:info, "“#{state.loaded.name}” was deleted. What's on screen is untouched."}
      })
      |> sync_url()
    else
      put_state(socket, %{server_layouts: remaining})
    end
  end

  defp decorate(layout, socket) do
    Map.put(
      layout,
      "can_edit",
      ScheduleLayoutDomainManager.can_edit?(layout, socket.assigns.current_user)
    )
  end

  defp valid_local_layout?(%{"id" => id, "name" => name, "entries" => entries})
       when is_binary(id) and is_binary(name) and is_list(entries),
       do: true

  defp valid_local_layout?(layout) do
    Logger.warning("Ignored a malformed layout in browser storage: #{inspect(layout)}")
    false
  end

  defp maybe_attach_hooks(socket) do
    if Map.get(socket.private, :schedule_layouts_hooks_attached?) do
      socket
    else
      socket
      |> LiveView.attach_hook("schedule-layouts:event", :handle_event, &hooked_event/3)
      |> LiveView.attach_hook("schedule-layouts:info", :handle_info, &hooked_info/2)
      |> LiveView.attach_hook("schedule-layouts:params", :handle_params, &hooked_params/3)
      |> put_in([Access.key(:private), :schedule_layouts_hooks_attached?], true)
    end
  end

  defp maybe_request_initial_data(socket) do
    if LiveView.connected?(socket) and !Map.get(socket.private, :schedule_layouts_requested?) do
      ScheduleLayoutPubSub.subscribe()
      ScheduleLayoutDomainManager.list_layouts(pid: self(), user: socket.assigns.current_user)
      put_in(socket, [Access.key(:private), :schedule_layouts_requested?], true)
    else
      socket
    end
  end

  # -- Presentation helpers --------------------------------------------------

  defp describe(:not_signed_in), do: "You need to be signed in."
  defp describe(:not_allowed), do: "You don't have permission to change it."
  defp describe(:not_found), do: "It no longer exists."
  defp describe(reason) when is_binary(reason), do: reason
  defp describe(reason), do: inspect(reason)

  defp truncate(text, limit) when is_binary(text) do
    if String.length(text) > limit do
      String.slice(text, 0, limit - 1) <> "…"
    else
      text
    end
  end

  defp random_ref, do: :crypto.strong_rand_bytes(8) |> Base.encode16(case: :lower)
end
