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

  @pubsub SimpleSyllabusReporter.PubSub
  @max_concurrent 1
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
    {:ok, %{queue: :queue.new(), in_flight: 0, max_concurrent: @max_concurrent}}
  end

  @impl true
  def handle_call(:status, _from, state) do
    {:reply, %{in_flight: state.in_flight, queued: :queue.len(state.queue)}, state}
  end

  @impl true
  def handle_cast({:enqueue, topic, event, messages, opts}, state) do
    new_state =
      if state.in_flight < state.max_concurrent do
        spawn_completion(self(), topic, event, messages, opts)
        %{state | in_flight: state.in_flight + 1}
      else
        %{state | queue: :queue.in({topic, event, messages, opts}, state.queue)}
      end

    broadcast_status(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info(:completion_done, state) do
    new_state =
      case :queue.out(state.queue) do
        {{:value, {topic, event, messages, opts}}, queue} ->
          spawn_completion(self(), topic, event, messages, opts)
          %{state | queue: queue}

        {:empty, _} ->
          %{state | in_flight: state.in_flight - 1}
      end

    broadcast_status(new_state)
    {:noreply, new_state}
  end

  defp broadcast_status(state) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      @status_topic,
      {:queue_status, %{in_flight: state.in_flight, queued: :queue.len(state.queue)}}
    )
  end

  defp spawn_completion(server, topic, event, messages, opts) do
    spawn(fn ->
      result =
        try do
          complete_sync(messages, opts)
        rescue
          e -> {:error, {:exception, Exception.message(e)}}
        catch
          :exit, reason -> {:error, {:exit, reason}}
          thrown -> {:error, {:thrown, thrown}}
        end

      Phoenix.PubSub.broadcast(@pubsub, topic, {event, result})
      send(server, :completion_done)
    end)
  end

  @spec complete_sync([message()], [option()]) :: result()
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
      {:ok, %{status: 200, body: body}} -> extract_content(body, opts[:schema])
      {:ok, %{status: status, body: body}} -> {:error, {status, extract_error_message(body)}}
      {:error, reason} -> {:error, reason}
    end
  end

  defp maybe_add_structured_output(body, nil), do: body

  defp maybe_add_structured_output(body, schema) do
    Map.put(body, :response_format, %{
      type: "json_schema",
      json_schema: %{name: "response", strict: true, schema: schema}
    })
  end

  defp extract_content(%{"choices" => [%{"message" => %{"content" => content}} | _]}, nil) do
    {:ok, content}
  end

  defp extract_content(%{"choices" => [%{"message" => %{"content" => content}} | _]}, _schema) do
    case Jason.decode(content) do
      {:ok, parsed} -> {:ok, parsed}
      {:error, _} -> {:error, {:invalid_json, content}}
    end
  end

  defp extract_content(body, _schema), do: {:error, {:unexpected_response, body}}

  defp extract_error_message(%{"error" => %{"message" => msg}}), do: msg
  defp extract_error_message(body), do: inspect(body)
end
