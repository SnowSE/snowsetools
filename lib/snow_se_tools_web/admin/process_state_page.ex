defmodule SnowSeToolsWeb.Admin.ProcessStatePage do
  @moduledoc """
  A LiveDashboard page for what the built-in Processes page doesn't show: the
  state a GenServer is holding, as `:sys.get_state/2` returns it.

  Lists this app's named processes (the domain managers and the like) with
  their message queue length and memory; clicking one shows its state. Read
  on the node the dashboard is pointed at.

  Admin-only, like the rest of the dashboard (see the router). State can hold
  anything a process keeps -- tokens and settings included -- so it stays
  behind that gate.
  """
  use Phoenix.LiveDashboard.PageBuilder

  # A busy or wedged process must not hang the dashboard.
  @state_timeout 2_000
  # Enough to read a domain manager's state; past this it is cut, not sent.
  @max_chars 200_000

  @impl true
  def menu_link(_session, _capabilities), do: {:ok, "GenServer state"}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, selected: nil, state_text: nil, state_error: nil)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <.live_table
      id="process-state-table"
      dom_id="process-state-table"
      page={@page}
      title="Named processes in this app"
      hint="Click a row to see the state it holds. The list refreshes with the dashboard; the state is read once, when you click."
      row_fetcher={&fetch_processes/2}
      row_attrs={&row_attrs/1}
      rows_name="processes"
      default_sort_by={:message_queue_len}
    >
      <:col field={:name} header="Name" sortable={:asc} />
      <:col field={:message_queue_len} header="Message queue" text_align="right" sortable={:desc} />
      <:col
        :let={process}
        field={:memory}
        header="Memory"
        text_align="right"
        sortable={:desc}
      >
        {format_bytes(process[:memory])}
      </:col>
      <:col field={:current_function} header="Current function" />
    </.live_table>

    <.card :if={@selected} title={"State of #{@selected}"} dom_id="process-state-value">
      <p :if={@state_error} class="text-danger mb-0">{@state_error}</p>
      <pre
        :if={@state_text}
        style="max-height: 70vh; overflow: auto; white-space: pre-wrap; font-size: 0.8rem; margin: 0;"
      >{@state_text}</pre>
    </.card>
    """
  end

  @impl true
  def handle_event("show_state", %{"name" => name}, socket) do
    node = socket.assigns.page.node

    case named_process(node, name) do
      nil ->
        {:noreply,
         assign(socket,
           selected: name,
           state_text: nil,
           state_error: "No process is registered under that name any more."
         )}

      registered ->
        {:noreply, assign(socket, [selected: name] ++ read_state(node, registered))}
    end
  end

  defp read_state(node, registered) do
    state =
      :erpc.call(node, :sys, :get_state, [registered, @state_timeout], @state_timeout + 1_000)

    text =
      state
      |> inspect(pretty: true, width: 100, limit: 500, printable_limit: 4_096)
      |> truncate()

    [state_text: text, state_error: nil]
  catch
    kind, reason ->
      [
        state_text: nil,
        state_error:
          "Couldn't read its state: #{Exception.format_banner(kind, reason) |> String.slice(0, 500)}. " <>
            "It may not be a GenServer, or it was too busy to answer within #{div(@state_timeout, 1000)} seconds."
      ]
  end

  defp truncate(text) when byte_size(text) <= @max_chars, do: text

  defp truncate(text),
    do: binary_part(text, 0, @max_chars) <> "\n\n… cut at #{@max_chars} characters."

  # Only names that are this app's, matched by string, so a name typed into
  # the event can never mint a new atom.
  defp named_process(node, name) do
    node
    |> app_names()
    |> Enum.find(&(inspect(&1) == name))
  end

  defp app_names(node) do
    node
    |> :erpc.call(Process, :registered, [])
    |> Enum.filter(&String.starts_with?(Atom.to_string(&1), "Elixir.SnowSeTools"))
  end

  defp fetch_processes(params, node) do
    %{search: search, sort_by: sort_by, sort_dir: sort_dir, limit: limit} = params

    rows =
      node
      |> app_names()
      |> Enum.flat_map(fn registered ->
        with pid when is_pid(pid) <- :erpc.call(node, Process, :whereis, [registered]),
             info when is_list(info) <-
               :erpc.call(node, Process, :info, [
                 pid,
                 [:message_queue_len, :memory, :current_function]
               ]) do
          [
            %{
              name: inspect(registered),
              message_queue_len: info[:message_queue_len],
              memory: info[:memory],
              current_function: format_mfa(info[:current_function])
            }
          ]
        else
          # Gone between listing and asking.
          _gone -> []
        end
      end)
      |> Enum.filter(&(is_nil(search) or String.contains?(&1.name, search)))

    sorted =
      rows
      |> Enum.sort_by(&Map.fetch!(&1, sort_by), sort_dir)
      |> Enum.take(limit)

    {sorted, length(rows)}
  end

  defp row_attrs(row) do
    [
      {"phx-click", "show_state"},
      {"phx-value-name", row.name},
      {"phx-page-loading", true},
      {"style", "cursor: pointer;"}
    ]
  end

  defp format_mfa({module, function, arity}), do: "#{inspect(module)}.#{function}/#{arity}"
  defp format_mfa(other), do: inspect(other)

  defp format_bytes(nil), do: ""
  defp format_bytes(bytes) when bytes < 1024, do: "#{bytes} B"
  defp format_bytes(bytes) when bytes < 1024 * 1024, do: "#{Float.round(bytes / 1024, 1)} KB"
  defp format_bytes(bytes), do: "#{Float.round(bytes / (1024 * 1024), 1)} MB"
end
