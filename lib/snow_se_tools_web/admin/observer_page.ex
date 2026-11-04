defmodule SnowSeToolsWeb.Admin.ObserverPage do
  @moduledoc """
  Observer in the browser: an application's supervision tree drawn left to
  right, and, for the process you click, what Observer's process window shows
  -- its details, the messages waiting in its mailbox, and (on request) the
  state it holds.

  LiveDashboard's own Applications page draws the tree too, but its process
  pop-up stops at the queue length; reading the mailbox and the state is the
  point of this page.

  Admin-only, like the rest of the dashboard: messages and state can hold
  anything a process has, tokens included.

  Everything is read on the node the dashboard is pointed at, by calling this
  module's `collect_tree/2`, `details/1` and `read_state/1` there.
  """
  use Phoenix.LiveDashboard.PageBuilder

  # Drawing.
  @node_w 260
  # Characters of a label that fit in a box at 12px monospace, with and
  # without a mailbox badge; the full name is in the hover title.
  @label_chars 33
  @label_chars_with_badge 27
  @node_h 26
  @gap_x 34
  @gap_y 6

  # A supervisor with more children than this (acceptor pools, task
  # supervisors) starts folded; click it to open it.
  @fold_over 12
  # How long one supervisor or process may take to answer before it is shown
  # as not answering, rather than holding up the whole tree.
  @call_timeout 1_000
  @state_timeout 2_000
  # Reading a mailbox copies it; a huge one is counted, not read.
  @max_messages_shown 50
  @max_queue_read 10_000
  @max_chars 100_000

  @impl true
  def menu_link(_session, _capabilities), do: {:ok, "Observer"}

  @impl true
  def mount(_params, _session, socket) do
    socket =
      socket
      |> assign(
        app: :snow_se_tools,
        toggled: MapSet.new(),
        selected: nil,
        details: nil,
        state_text: nil,
        state_error: nil
      )
      |> load_apps()
      |> load_tree()

    {:ok, socket}
  end

  @impl true
  def handle_refresh(socket) do
    {:noreply, socket |> load_tree() |> load_details()}
  end

  @impl true
  def handle_event("observer_app", %{"app" => app}, socket) do
    case Enum.find(socket.assigns.apps, &(Atom.to_string(&1) == app)) do
      nil ->
        {:noreply, socket}

      app ->
        {:noreply,
         socket
         |> assign(app: app, toggled: MapSet.new(), selected: nil, details: nil)
         |> clear_state()
         |> load_tree()}
    end
  end

  def handle_event("observer_toggle", %{"pid" => pid}, socket) do
    if known_pid?(socket, pid) do
      toggled = socket.assigns.toggled

      toggled =
        if MapSet.member?(toggled, pid),
          do: MapSet.delete(toggled, pid),
          else: MapSet.put(toggled, pid)

      {:noreply, socket |> assign(toggled: toggled) |> load_tree()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("observer_select", %{"pid" => pid}, socket) do
    if known_pid?(socket, pid) do
      {:noreply, socket |> assign(selected: pid) |> clear_state() |> load_details()}
    else
      {:noreply, socket}
    end
  end

  def handle_event("observer_read_state", _params, socket) do
    case socket.assigns.selected do
      nil ->
        {:noreply, socket}

      pid ->
        case remote(socket, :read_state, [to_pid(pid)]) do
          {:ok, text} -> {:noreply, assign(socket, state_text: text, state_error: nil)}
          {:error, message} -> {:noreply, assign(socket, state_text: nil, state_error: message)}
        end
    end
  end

  def handle_event("observer_close", _params, socket) do
    {:noreply, socket |> assign(selected: nil, details: nil) |> clear_state()}
  end

  # -- Loading ---------------------------------------------------------------

  defp load_apps(socket) do
    apps =
      case remote(socket, :running_apps, []) do
        {:ok, apps} -> apps
        _error -> [socket.assigns.app]
      end

    assign(socket, :apps, apps)
  end

  defp load_tree(socket) do
    case remote(socket, :collect_tree, [socket.assigns.app, socket.assigns.toggled]) do
      {:ok, tree} ->
        {nodes, edges, rows, depth} = layout(tree)

        assign(socket,
          tree_error: nil,
          nodes: nodes,
          edges: edges,
          rows: rows,
          depth: depth,
          known: MapSet.new(nodes, & &1.pid)
        )

      {:error, message} ->
        assign(socket,
          tree_error: message,
          nodes: [],
          edges: [],
          rows: 0,
          depth: 0,
          known: MapSet.new()
        )
    end
  end

  defp load_details(%{assigns: %{selected: nil}} = socket), do: socket

  defp load_details(socket) do
    case remote(socket, :details, [to_pid(socket.assigns.selected)]) do
      {:ok, details} -> assign(socket, :details, details)
      {:error, message} -> assign(socket, :details, %{gone: message})
    end
  end

  defp clear_state(socket), do: assign(socket, state_text: nil, state_error: nil)

  # Only pids drawn in the tree (or linked from the selected one) are acted
  # on, so an event can't be used to poke at an arbitrary process.
  defp known_pid?(socket, pid) do
    MapSet.member?(socket.assigns.known, pid) or
      pid in Map.get(socket.assigns.details || %{}, :linked_pids, [])
  end

  defp remote(socket, function, args) do
    node = socket.assigns.page.node
    :erpc.call(node, __MODULE__, function, args, @state_timeout + 3_000)
  catch
    kind, reason -> {:error, Exception.format_banner(kind, reason) |> String.slice(0, 300)}
  end

  defp to_pid(pid) when is_binary(pid), do: :erlang.list_to_pid(String.to_charlist(pid))

  # -- Run on the observed node ------------------------------------------------

  @doc false
  def running_apps do
    {:ok, :application.which_applications() |> Enum.map(&elem(&1, 0)) |> Enum.sort()}
  end

  @doc false
  def collect_tree(app, toggled) do
    with master when is_pid(master) <- :application_controller.get_master(app),
         {root, _module} when is_pid(root) <- :application_master.get_child(master) do
      {:ok, build(root, app, :supervisor, toggled)}
    else
      _not_running -> {:error, "#{app} has no supervision tree running on this node."}
    end
  end

  defp build(pid, id, type, toggled) do
    key = pid_key(pid)
    info = Process.info(pid, [:registered_name, :message_queue_len, :dictionary]) || []

    node = %{
      pid: key,
      label: label(pid, id, info),
      type: type,
      queue: Keyword.get(info, :message_queue_len, 0),
      children: [],
      child_count: 0,
      open?: false,
      answering?: true
    }

    if type == :supervisor do
      case which_children(pid) do
        {:ok, children} ->
          open? = length(children) <= @fold_over != MapSet.member?(toggled, key)

          kids =
            if open? do
              Enum.map(children, fn
                {child_id, child, child_type, _modules} when is_pid(child) ->
                  build(child, child_id, child_type, toggled)

                {child_id, status, child_type, _modules} ->
                  not_running(child_id, status, child_type)
              end)
            else
              []
            end

          %{node | children: kids, child_count: length(children), open?: open?}

        :not_answering ->
          %{node | answering?: false}
      end
    else
      node
    end
  end

  defp not_running(id, status, type) do
    %{
      pid: nil,
      label: "#{short(inspect(id))} (#{status})",
      type: type,
      queue: 0,
      children: [],
      child_count: 0,
      open?: false,
      answering?: true
    }
  end

  # Supervisors and dynamic supervisors both answer :which_children; one
  # that doesn't answer in time is drawn as such instead of hanging the page.
  defp which_children(pid) do
    {:ok, GenServer.call(pid, :which_children, @call_timeout)}
  catch
    :exit, _reason -> :not_answering
  end

  defp label(pid, id, info) do
    cond do
      is_atom(info[:registered_name]) and info[:registered_name] not in [nil, []] ->
        short(inspect(info[:registered_name]))

      id not in [:undefined, nil] ->
        short(inspect(id))

      initial = get_in(info, [:dictionary, :"$initial_call"]) ->
        short(format_mfa(initial))

      true ->
        pid_key(pid)
    end
  end

  @doc false
  def details(pid) do
    keys = [
      :registered_name,
      :status,
      :message_queue_len,
      :memory,
      :reductions,
      :current_function,
      :initial_call,
      :links,
      :monitors,
      :monitored_by,
      :trap_exit,
      :total_heap_size,
      :dictionary
    ]

    case Process.info(pid, keys) do
      nil ->
        {:error, "That process has exited."}

      info ->
        queue = info[:message_queue_len]
        dictionary = info[:dictionary] || []

        {:ok,
         %{
           pid: pid_key(pid),
           fields: [
             {"Registered name", registered(info[:registered_name])},
             {"Status", inspect(info[:status])},
             {"Initial call",
              format_mfa(Keyword.get(dictionary, :"$initial_call", info[:initial_call]))},
             {"Current function", format_mfa(info[:current_function])},
             {"Message queue", Integer.to_string(queue)},
             {"Memory", format_bytes(info[:memory])},
             {"Total heap", "#{info[:total_heap_size]} words"},
             {"Reductions", Integer.to_string(info[:reductions])},
             {"Traps exits", inspect(info[:trap_exit])},
             {"Monitors", Integer.to_string(length(info[:monitors] || []))},
             {"Monitored by", Integer.to_string(length(info[:monitored_by] || []))}
           ],
           linked_pids: for(link <- info[:links] || [], is_pid(link), do: pid_key(link)),
           linked_ports: for(link <- info[:links] || [], is_port(link), do: inspect(link)),
           queue: queue,
           messages: messages(pid, queue)
         }}
    end
  end

  defp messages(_pid, 0), do: {:ok, []}

  defp messages(_pid, queue) when queue > @max_queue_read,
    do: {:too_many, queue}

  defp messages(pid, _queue) do
    case Process.info(pid, :messages) do
      {:messages, messages} ->
        {:ok,
         messages
         |> Enum.take(@max_messages_shown)
         |> Enum.map(&inspect(&1, pretty: true, width: 90, limit: 50, printable_limit: 1_024))}

      nil ->
        {:ok, []}
    end
  end

  @doc false
  def read_state(pid) do
    state = :sys.get_state(pid, @state_timeout)

    text =
      state
      |> inspect(pretty: true, width: 100, limit: 500, printable_limit: 4_096)
      |> truncate()

    {:ok, text}
  catch
    :exit, _reason ->
      {:error,
       "It didn't answer within #{div(@state_timeout, 1000)} seconds. Only OTP processes " <>
         "(GenServer, Agent, :gen_statem, supervisors) can report their state, and one busy " <>
         "handling a long message can't answer until it's done."}
  end

  defp truncate(text) when byte_size(text) <= @max_chars, do: text

  defp truncate(text),
    do: binary_part(text, 0, @max_chars) <> "\n\n… cut at #{@max_chars} characters."

  defp registered(name) when is_atom(name) and name not in [nil, []], do: inspect(name)
  defp registered(_none), do: "—"

  defp pid_key(pid), do: pid |> :erlang.pid_to_list() |> List.to_string()

  defp short(text) do
    text = String.replace_prefix(text, "Elixir.", "")
    if String.length(text) > 80, do: String.slice(text, 0, 79) <> "…", else: text
  end

  defp format_mfa({module, function, arity}) when is_atom(module),
    do: "#{inspect(module)}.#{function}/#{arity}"

  defp format_mfa(other), do: inspect(other)

  defp format_bytes(nil), do: "—"
  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"

  # -- Layout --------------------------------------------------------------------

  # A tidy tree, left to right: each leaf takes the next row, and a parent
  # sits midway between its first and last child.
  defp layout(tree) do
    {nodes, edges, rows, depth, _y} = place(tree, 0, 0)
    {nodes, edges, rows, depth}
  end

  defp place(%{children: []} = node, depth, row) do
    {[position(node, depth, row)], [], row + 1, depth, row}
  end

  defp place(node, depth, row) do
    {child_nodes, child_edges, next_row, max_depth, ys} =
      Enum.reduce(node.children, {[], [], row, depth, []}, fn child, {ns, es, r, d, ys} ->
        {cn, ce, nr, cd, cy} = place(child, depth + 1, r)
        {ns ++ cn, es ++ ce, nr, max(d, cd), ys ++ [cy]}
      end)

    y = (List.first(ys) + List.last(ys)) / 2
    edges = Enum.map(ys, &{depth, y, depth + 1, &1})

    {[position(node, depth, y) | child_nodes], edges ++ child_edges, next_row, max_depth, y}
  end

  defp position(node, depth, row) do
    node
    |> Map.drop([:children])
    |> Map.merge(%{x: depth * (@node_w + @gap_x), y: row * (@node_h + @gap_y)})
  end

  defp edge_path({from_depth, from_row, to_depth, to_row}) do
    x1 = from_depth * (@node_w + @gap_x) + @node_w
    y1 = from_row * (@node_h + @gap_y) + @node_h / 2
    x2 = to_depth * (@node_w + @gap_x)
    y2 = to_row * (@node_h + @gap_y) + @node_h / 2
    mid = x1 + @gap_x / 2
    "M#{x1},#{y1} H#{mid} V#{y2} H#{x2}"
  end

  # -- Rendering -------------------------------------------------------------------

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        width: (assigns.depth + 1) * (@node_w + @gap_x),
        height: max(assigns.rows, 1) * (@node_h + @gap_y),
        node_w: @node_w,
        node_h: @node_h
      )

    ~H"""
    <div id="observer-page">
      <.card title="Supervision tree" dom_id="observer-tree">
        <form id="observer-app-form" phx-change="observer_app" class="mb-3" style="max-width: 22rem;">
          <select name="app" class="custom-select form-control">
            <option :for={app <- @apps} value={app} selected={app == @app}>{app}</option>
          </select>
        </form>

        <p class="text-muted small mb-2">
          Click a process for its details and mailbox. Click a supervisor's <b>+</b>/<b>−</b>
          to open or fold it; ones with more than {fold_over()} children start folded.
          A red badge is a process with messages waiting.
        </p>

        <p :if={@tree_error} class="text-danger">{@tree_error}</p>

        <div style="overflow: auto; max-height: 70vh; border: 1px solid #e5e7eb; border-radius: 6px; padding: 8px; background: #fafafa;">
          <svg
            id="observer-svg"
            width={@width}
            height={@height}
            style="font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: 12px; display: block;"
          >
            <path
              :for={edge <- @edges}
              d={edge_path(edge)}
              fill="none"
              stroke="#9ca3af"
              stroke-width="1"
            />
            <g
              :for={node <- @nodes}
              id={node.pid && "observer-node-#{node.pid}"}
              data-type={node.type}
              phx-click={node.pid && "observer_select"}
              phx-value-pid={node.pid}
              style={node.pid && "cursor: pointer;"}
            >
              <title>{node.label} {node.pid}</title>
              <rect
                x={node.x}
                y={node.y}
                width={@node_w}
                height={@node_h}
                rx="4"
                fill={node_fill(node, @selected)}
                stroke={node_stroke(node, @selected)}
                stroke-width={if node.pid && node.pid == @selected, do: 2, else: 1}
              />
              <text x={node.x + 8} y={node.y + 17} fill={node_text(node)}>
                {fit(node.label, node.queue)}
              </text>
              <g :if={node.queue > 0}>
                <rect
                  x={node.x + @node_w - 44}
                  y={node.y + 5}
                  width="36"
                  height="16"
                  rx="8"
                  fill="#dc2626"
                />
                <text
                  x={node.x + @node_w - 26}
                  y={node.y + 17}
                  fill="#fff"
                  text-anchor="middle"
                  font-size="10"
                >
                  {queue_label(node.queue)}
                </text>
              </g>
              <g
                :if={node.type == :supervisor and node.child_count > 0 and node.pid}
                id={"observer-toggle-#{node.pid}"}
                phx-click="observer_toggle"
                phx-value-pid={node.pid}
              >
                <rect
                  x={node.x + @node_w - 2}
                  y={node.y + 4}
                  width="30"
                  height="18"
                  rx="4"
                  fill="#e5e7eb"
                  stroke="#9ca3af"
                />
                <text x={node.x + @node_w + 13} y={node.y + 17} text-anchor="middle" font-size="11">
                  {if node.open?, do: "−", else: "+#{node.child_count}"}
                </text>
              </g>
            </g>
          </svg>
        </div>
      </.card>

      <.card :if={@details} title={"Process #{@selected}"} dom_id="observer-details">
        <div :if={@details[:gone]} class="text-danger">{@details[:gone]}</div>

        <div :if={!@details[:gone]}>
          <div class="text-right mb-2">
            <button type="button" class="btn btn-sm btn-link" phx-click="observer_close">
              Close
            </button>
          </div>

          <table class="table table-sm mb-3">
            <tbody>
              <tr :for={{field, value} <- @details.fields}>
                <th style="width: 12rem;">{field}</th>
                <td style="font-family: ui-monospace, monospace;">{value}</td>
              </tr>
              <tr>
                <th>Links</th>
                <td style="font-family: ui-monospace, monospace;">
                  <span :if={@details.linked_pids == [] and @details.linked_ports == []}>—</span>
                  <a
                    :for={link <- @details.linked_pids}
                    href="#"
                    class="mr-2"
                    phx-click="observer_select"
                    phx-value-pid={link}
                  >{link}</a>
                  <span :for={port <- @details.linked_ports} class="mr-2">{port}</span>
                </td>
              </tr>
            </tbody>
          </table>

          <h6>Mailbox</h6>
          <div id="observer-mailbox" class="mb-3">
            <%= case @details.messages do %>
              <% {:ok, []} -> %>
                <p class="text-muted small mb-0">Empty.</p>
              <% {:ok, messages} -> %>
                <p :if={@details.queue > length(messages)} class="text-muted small">
                  The first {length(messages)} of {@details.queue}.
                </p>
                <pre
                  :for={message <- messages}
                  style="white-space: pre-wrap; font-size: 0.8rem; background: #f3f4f6; padding: 6px 8px; border-radius: 4px; margin-bottom: 6px;"
                >{message}</pre>
              <% {:too_many, queue} -> %>
                <p class="text-danger small mb-0">
                  {queue} messages waiting — too many to read without copying them all.
                </p>
            <% end %>
          </div>

          <h6>State</h6>
          <button
            type="button"
            id="observer-read-state"
            class="btn btn-sm btn-outline-primary mb-2"
            phx-click="observer_read_state"
            phx-page-loading
          >
            {if @state_text, do: "Read again", else: "Read state"}
          </button>
          <p :if={@state_error} class="text-danger small">{@state_error}</p>
          <pre
            :if={@state_text}
            id="observer-state"
            style="max-height: 50vh; overflow: auto; white-space: pre-wrap; font-size: 0.8rem; background: #f3f4f6; padding: 8px; border-radius: 4px;"
          >{@state_text}</pre>
        </div>
      </.card>
    </div>
    """
  end

  defp fold_over, do: @fold_over

  defp fit(label, queue) do
    room = if queue > 0, do: @label_chars_with_badge, else: @label_chars
    if String.length(label) > room, do: String.slice(label, 0, room - 1) <> "…", else: label
  end

  defp node_fill(%{pid: pid}, pid) when not is_nil(pid), do: "#dbeafe"
  defp node_fill(%{answering?: false}, _selected), do: "#fef3c7"
  defp node_fill(%{pid: nil}, _selected), do: "#f3f4f6"
  defp node_fill(%{type: :supervisor}, _selected), do: "#eef2ff"
  defp node_fill(_node, _selected), do: "#ffffff"

  defp node_stroke(%{pid: pid}, pid) when not is_nil(pid), do: "#2563eb"
  defp node_stroke(%{type: :supervisor}, _selected), do: "#6366f1"
  defp node_stroke(_node, _selected), do: "#d1d5db"

  defp node_text(%{pid: nil}), do: "#9ca3af"
  defp node_text(_node), do: "#111827"

  defp queue_label(queue) when queue > 999, do: "999+"
  defp queue_label(queue), do: Integer.to_string(queue)
end
