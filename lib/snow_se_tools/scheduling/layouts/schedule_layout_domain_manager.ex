defmodule SnowSeTools.Scheduling.ScheduleLayoutDomainManager do
  @moduledoc """
  Owns saved schedule viewer layouts: listing, writing and deleting them, and
  asking the configured model for a name to propose in the save dialog.

  Permission lives here rather than in the LiveView, so a forged event cannot
  overwrite a layout the user may only read. A layout is editable by the person
  who saved it, and shared layouts are additionally editable by super users.
  """

  use GenServer
  require Logger

  alias SnowSeTools.AI.AsyncCompletions
  alias SnowSeTools.Data.Access
  alias SnowSeTools.Scheduling.{ScheduleLayoutDb, ScheduleLayoutPubSub}

  @ai_topic "schedule_layouts:naming"

  @name_schema %{
    "type" => "object",
    "properties" => %{
      "name" => %{"type" => "string"},
      "alternates" => %{
        "type" => "array",
        "items" => %{"type" => "string"}
      }
    },
    "required" => ["name", "alternates"],
    "additionalProperties" => false
  }

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, :ok, name: __MODULE__)
  end

  def list_layouts(pid: pid, user: user) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:list_layouts, pid, user})
  end

  def save_layout(pid: pid, user: user, attrs: attrs) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:save_layout, pid, user, attrs})
  end

  def update_layout(pid: pid, user: user, layout_id: layout_id, attrs: attrs) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:update_layout, pid, user, layout_id, attrs})
  end

  def delete_layout(pid: pid, user: user, layout_id: layout_id) when is_pid(pid) do
    GenServer.cast(__MODULE__, {:delete_layout, pid, user, layout_id})
  end

  @doc """
  Asks the model for a layout name. The caller already has a usable local name
  and must not wait on this — the reply arrives as
  `{:schedule_layouts, {:name_suggested, request_ref, names}}` or
  `{:schedule_layouts, {:name_suggestion_failed, request_ref, reason}}`.
  """
  def suggest_name(
        pid: pid,
        request_ref: request_ref,
        card_labels: card_labels,
        term_name: term_name
      )
      when is_pid(pid) and is_binary(request_ref) do
    GenServer.cast(__MODULE__, {:suggest_name, pid, request_ref, card_labels, term_name})
  end

  @doc "Can `user` overwrite, rename or delete `layout`?"
  def can_edit?(layout, user) do
    cond do
      is_nil(user) -> false
      layout["user_id"] == user.id -> true
      layout["scope"] == "shared" and Access.admin?(user) -> true
      true -> false
    end
  end

  @impl true
  def init(:ok) do
    case ScheduleLayoutDb.bootstrap_tables() do
      :ok ->
        Phoenix.PubSub.subscribe(SnowSeTools.PubSub, @ai_topic)
        {:ok, %{naming_requests: %{}}}

      {:error, reason} ->
        Logger.error("ScheduleLayoutDomainManager could not bootstrap tables: #{inspect(reason)}")
        {:stop, {:bootstrap_failed, reason}}
    end
  end

  @impl true
  def handle_cast({:list_layouts, pid, user}, state) do
    case user do
      %{id: user_id} ->
        case ScheduleLayoutDb.list_visible_to(user_id: user_id) do
          {:ok, layouts} ->
            send(pid, {:schedule_layouts, {:layouts_listed, decorate(layouts, user)}})

          {:error, reason} ->
            Logger.error("Could not list schedule layouts: #{inspect(reason)}")
            send(pid, {:schedule_layouts, {:layouts_error, reason}})
        end

      _no_user ->
        Logger.error("Refusing to list schedule layouts without a signed-in user")
        send(pid, {:schedule_layouts, {:layouts_error, :not_signed_in}})
    end

    {:noreply, state}
  end

  def handle_cast({:save_layout, pid, user, attrs}, state) do
    case user do
      %{id: user_id} ->
        result =
          ScheduleLayoutDb.create(
            name: attrs.name,
            scope: attrs.scope,
            user_id: user_id,
            term_code: attrs.term_code,
            entries: attrs.entries
          )

        reply_with_layout(pid, user, result, :layout_saved, "save")

      _no_user ->
        Logger.error("Refusing to save a schedule layout without a signed-in user")
        send(pid, {:schedule_layouts, {:layout_error, :not_signed_in}})
    end

    {:noreply, state}
  end

  def handle_cast({:update_layout, pid, user, layout_id, attrs}, state) do
    with {:ok, layout} <- ScheduleLayoutDb.get(layout_id),
         true <- can_edit?(layout, user) do
      result =
        ScheduleLayoutDb.update(
          layout_id: layout_id,
          name: Map.get(attrs, :name),
          scope: Map.get(attrs, :scope),
          entries: Map.get(attrs, :entries)
        )

      reply_with_layout(pid, user, result, :layout_saved, "update")
    else
      false ->
        Logger.warning(
          "Refused layout update: user=#{inspect(user && user.email)} layout=#{layout_id}"
        )

        send(pid, {:schedule_layouts, {:layout_error, :not_allowed}})

      {:error, reason} ->
        Logger.error("Could not load layout #{layout_id} for update: #{inspect(reason)}")
        send(pid, {:schedule_layouts, {:layout_error, reason}})
    end

    {:noreply, state}
  end

  def handle_cast({:delete_layout, pid, user, layout_id}, state) do
    with {:ok, layout} <- ScheduleLayoutDb.get(layout_id),
         true <- can_edit?(layout, user) do
      case ScheduleLayoutDb.delete(layout_id) do
        :ok ->
          ScheduleLayoutPubSub.broadcast_layout_deleted(layout_id)
          send(pid, {:schedule_layouts, {:layout_deleted, layout_id}})

        {:error, reason} ->
          Logger.error("Could not delete layout #{layout_id}: #{inspect(reason)}")
          send(pid, {:schedule_layouts, {:layout_error, reason}})
      end
    else
      false ->
        Logger.warning(
          "Refused layout delete: user=#{inspect(user && user.email)} layout=#{layout_id}"
        )

        send(pid, {:schedule_layouts, {:layout_error, :not_allowed}})

      {:error, reason} ->
        Logger.error("Could not load layout #{layout_id} for delete: #{inspect(reason)}")
        send(pid, {:schedule_layouts, {:layout_error, reason}})
    end

    {:noreply, state}
  end

  def handle_cast({:suggest_name, pid, request_ref, card_labels, term_name}, state) do
    AsyncCompletions.complete(
      @ai_topic,
      {:layout_name, request_ref},
      naming_messages(card_labels: card_labels, term_name: term_name),
      schema: @name_schema
    )

    {:noreply, put_in(state.naming_requests[request_ref], pid)}
  end

  @impl true
  def handle_info({{:layout_name, request_ref}, result}, state) do
    {pid, naming_requests} = Map.pop(state.naming_requests, request_ref)

    if is_pid(pid) do
      send(pid, {:schedule_layouts, naming_event(request_ref, result)})
    else
      Logger.warning("Dropped a layout name suggestion for unknown request #{request_ref}")
    end

    {:noreply, %{state | naming_requests: naming_requests}}
  end

  def handle_info(message, state) do
    Logger.debug("ScheduleLayoutDomainManager ignored #{inspect(message)}")
    {:noreply, state}
  end

  # A mocked or schema-less completion comes back without a name. That is not
  # an outage — the dialog already holds a locally generated name — so it is
  # reported as a failed suggestion rather than an error the user must act on.
  defp naming_event(request_ref, {:ok, %{"name" => name} = response}) when is_binary(name) do
    alternates =
      response
      |> Map.get("alternates", [])
      |> Enum.filter(&is_binary/1)

    {:name_suggested, request_ref, [name | alternates] |> Enum.uniq() |> Enum.take(4)}
  end

  defp naming_event(request_ref, {:ok, unexpected}) do
    Logger.info("Layout naming returned no usable name: #{inspect(unexpected)}")
    {:name_suggestion_failed, request_ref, :no_name_in_response}
  end

  defp naming_event(request_ref, {:error, reason}) do
    Logger.error("Layout naming failed: #{inspect(reason)}")
    {:name_suggestion_failed, request_ref, reason}
  end

  defp naming_messages(card_labels: card_labels, term_name: term_name) do
    [
      %{
        role: "system",
        content: """
        You name saved layouts in a college course scheduling tool. A layout is a
        set of schedule cards a scheduler arranged on screen: individual
        professors, individual rooms, program semesters, and overlay groups that
        draw several of those on one week grid together.

        Return one short name plus up to three alternates. Each name must be
        under 50 characters, describe what the layout is for rather than listing
        every card, and use no quotation marks. Prefer the vocabulary of academic
        scheduling: teaching load, room usage, conflict check, coverage, advising.
        """
      },
      %{
        role: "user",
        content: """
        Term: #{term_name || "unknown"}

        Cards on screen:
        #{Enum.map_join(card_labels, "\n", &"- #{&1}")}
        """
      }
    ]
  end

  defp reply_with_layout(pid, user, {:ok, layout}, event, _action) do
    ScheduleLayoutPubSub.broadcast_layout_saved(layout)
    send(pid, {:schedule_layouts, {event, decorate(layout, user)}})
  end

  defp reply_with_layout(pid, _user, {:error, reason}, _event, action) do
    Logger.error("Could not #{action} schedule layout: #{inspect(reason)}")
    send(pid, {:schedule_layouts, {:layout_error, reason}})
  end

  defp decorate(layouts, user) when is_list(layouts),
    do: Enum.map(layouts, &decorate(&1, user))

  defp decorate(layout, user) when is_map(layout),
    do: Map.put(layout, "can_edit", can_edit?(layout, user))
end
