defmodule SimpleSyllabusReporter.AI.AsyncCompletions do
  @moduledoc """
  GenServer that queues AI completions and limits concurrency, broadcasting results via PubSub.

  Completions beyond the concurrency limit are queued and dispatched as in-flight slots free up.

  ## Usage

      AsyncCompletions.complete("my_topic", :my_event, messages)
      AsyncCompletions.complete("my_topic", :my_event, messages, schema: schema)

      # In a LiveView or GenServer subscribed to "my_topic":
      def handle_info({:my_event, {:ok, content}}, state), do: ...
      def handle_info({:my_event, {:error, reason}}, state), do: ...

  """

  use GenServer
  require Logger

  alias SimpleSyllabusReporter.AI.CompletionLog

  @pubsub SimpleSyllabusReporter.PubSub
  @max_concurrent 3
  @status_topic "async_completions:status"

  @type message :: %{role: String.t(), content: String.t()}
  @type option :: {:schema, map()}
  @type result :: {:ok, String.t() | map()} | {:error, term()}

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def status_topic, do: @status_topic

  def status, do: GenServer.call(__MODULE__, :status)

  @spec complete(String.t(), term(), [message()], [option()]) :: :ok
  def complete(topic, event, messages, opts \\ []) do
    GenServer.cast(__MODULE__, {:enqueue, topic, event, messages, opts})
  end

  @impl true
  def init(_opts) do
    {:ok,
     %{
       queue: :queue.new(),
       in_flight: 0,
       max_concurrent: @max_concurrent,
       monitors: %{},
       recently_failed: []
     }}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, build_status(state), state}
  end

  @impl true
  def handle_cast({:enqueue, topic, event, messages, opts}, state) do
    new_state =
      if state.in_flight < state.max_concurrent do
        ref = spawn_completion(topic, event, messages, opts)

        %{
          state
          | in_flight: state.in_flight + 1,
            monitors: Map.put(state.monitors, ref, {topic, event})
        }
      else
        %{state | queue: :queue.in({topic, event, messages, opts}, state.queue)}
      end

    broadcast_status(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, :normal}, state) do
    {_info, monitors} = Map.pop(state.monitors, ref)
    new_state = drain_queue(%{state | monitors: monitors})
    broadcast_status(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    {info, monitors} = Map.pop(state.monitors, ref, nil)

    if info do
      {topic, event} = info
      error = worker_error(reason)

      Logger.error(
        "Completion worker crashed: topic=#{topic} event=#{inspect(event)} reason=#{inspect(reason)}"
      )

      Phoenix.PubSub.broadcast(@pubsub, topic, {event, {:error, error}})

      failure = %{
        topic: topic,
        event: event,
        reason: inspect(error),
        failed_at: DateTime.utc_now()
      }

      recently_failed = Enum.take([failure | state.recently_failed], 50)
      new_state = drain_queue(%{state | monitors: monitors, recently_failed: recently_failed})
      broadcast_status(new_state)
      {:noreply, new_state}
    else
      new_state = drain_queue(%{state | monitors: monitors})
      broadcast_status(new_state)
      {:noreply, new_state}
    end
  end

  defp broadcast_status(state) do
    Phoenix.PubSub.broadcast(@pubsub, @status_topic, {:queue_status, build_status(state)})
  end

  defp build_status(state) do
    in_flight_items = Map.values(state.monitors)

    queued_items =
      state.queue
      |> :queue.to_list()
      |> Enum.map(fn {topic, event, _messages, _opts} -> {topic, event} end)

    %{
      in_flight: state.in_flight,
      queued: :queue.len(state.queue),
      in_flight_items: in_flight_items,
      queued_items: queued_items,
      recently_failed: state.recently_failed
    }
  end

  defp worker_error({exception, _stacktrace}) when is_exception(exception) do
    {:exception, Exception.message(exception)}
  end

  defp worker_error(reason), do: {:worker_crashed, reason}

  defp drain_queue(state) do
    case :queue.out(state.queue) do
      {{:value, {topic, event, messages, opts}}, queue} ->
        ref = spawn_completion(topic, event, messages, opts)
        %{state | queue: queue, monitors: Map.put(state.monitors, ref, {topic, event})}

      {:empty, _} ->
        %{state | in_flight: state.in_flight - 1}
    end
  end

  defp spawn_completion(topic, event, messages, opts) do
    {_pid, ref} =
      spawn_monitor(fn ->
        {result, thinking} = complete_sync(messages, opts)
        config = Application.fetch_env!(:simple_syllabus_reporter, :ai)

        CompletionLog.record(
          topic,
          event,
          config[:model],
          config[:endpoint],
          messages,
          result,
          thinking
        )

        Phoenix.PubSub.broadcast(@pubsub, topic, {event, result})
      end)

    ref
  end

  @spec complete_sync([message()], [option()]) :: {result(), String.t() | nil}
  defp complete_sync(messages, opts) do
    config = Application.fetch_env!(:simple_syllabus_reporter, :ai)

    Logger.info(
      "AI completion: endpoint=#{config[:endpoint]} model=#{config[:model]} messages=#{length(messages)}"
    )

    body =
      %{model: config[:model], messages: messages}
      |> maybe_add_structured_output(opts[:schema])

    case Req.post(config[:endpoint],
           json: body,
           headers: [{"authorization", "Bearer #{config[:api_key]}"}],
           receive_timeout: :timer.minutes(10)
         ) do
      {:ok, %{status: 200, body: body}} ->
        thinking = extract_thinking(body)
        result = extract_content(body, opts[:schema])
        {result, thinking}

      {:ok, %{status: status, body: body}} ->
        {{:error, {status, extract_error_message(body)}}, nil}

      {:error, reason} ->
        {{:error, reason}, nil}
    end
  end

  defp maybe_add_structured_output(body, nil), do: body

  defp maybe_add_structured_output(body, schema) do
    Map.put(body, :response_format, %{
      type: "json_schema",
      json_schema: %{name: "response", strict: true, schema: schema}
    })
  end

  defp extract_thinking(%{"choices" => [%{"message" => message} | _]}) do
    cond do
      is_binary(message["reasoning_content"]) and message["reasoning_content"] != "" ->
        message["reasoning_content"]

      is_list(message["content"]) ->
        case Enum.find(message["content"], &(&1["type"] == "thinking")) do
          %{"thinking" => t} when is_binary(t) -> t
          _ -> nil
        end

      true ->
        nil
    end
  end

  defp extract_thinking(_), do: nil

  defp extract_content(%{"choices" => [%{"message" => %{"content" => content}} | _]}, nil)
       when is_binary(content) do
    {:ok, content}
  end

  defp extract_content(%{"choices" => [%{"message" => %{"content" => blocks}} | _]}, nil)
       when is_list(blocks) do
    text =
      Enum.find_value(blocks, "", fn
        %{"type" => "text", "text" => t} -> t
        _ -> false
      end)

    {:ok, text}
  end

  defp extract_content(%{"choices" => [%{"message" => %{"content" => content}} | _]}, _schema)
       when is_binary(content) do
    case Jason.decode(content) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, _} -> {:error, {:invalid_json, content}}
    end
  end

  defp extract_content(%{"choices" => [%{"message" => %{"content" => blocks}} | _]}, _schema)
       when is_list(blocks) do
    text =
      Enum.find_value(blocks, "", fn
        %{"type" => "text", "text" => t} -> t
        _ -> false
      end)

    case Jason.decode(text) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, _} -> {:error, {:invalid_json, text}}
    end
  end

  defp extract_content(body, _schema), do: {:error, {:unexpected_response, body}}

  defp extract_error_message(%{"error" => %{"message" => msg}}), do: msg
  defp extract_error_message(body), do: inspect(body)
end
