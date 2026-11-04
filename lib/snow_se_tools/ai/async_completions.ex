defmodule SnowSeTools.AI.AsyncCompletions do
  @moduledoc """
  GenServer that queues AI completions and limits concurrency, broadcasting results via PubSub.

  Completions beyond the concurrency limit are queued and dispatched as in-flight slots free up.

  A completion may name a `:lane`; completions in the same lane run one at a
  time, in the order they were asked for, while others keep using the free
  slots. The AI server shares one context window among the requests it runs at
  once, so a caller whose prompts are large (a curriculum review is ~32k tokens
  with its answer, against a 66k window) uses a lane rather than crowding the
  server out.

  An engine error from the server -- a 5xx, or LM Studio's 400 wrapping one --
  is retried once after a short pause before it is reported: they are often
  a one-off, such as its speculative-decoding fault under batched requests.

  ## Usage

      AsyncCompletions.complete("my_topic", :my_event, messages)
      AsyncCompletions.complete("my_topic", :my_event, messages, schema: schema)

      # In a LiveView or GenServer subscribed to "my_topic":
      def handle_info({:my_event, {:ok, content}}, state), do: ...
      def handle_info({:my_event, {:error, reason}}, state), do: ...

  """

  use GenServer
  require Logger

  alias SnowSeTools.AI.Settings

  alias SnowSeTools.AI.CompletionLog
  alias SnowSeTools.Telemetry.Events

  @pubsub SnowSeTools.PubSub
  @max_concurrent 3
  # Requests beyond this are rejected (with an error broadcast) instead of
  # growing the queue without bound.
  @max_queued 500
  @retry_pause :timer.seconds(5)
  @retries 1
  @status_topic "async_completions:status"

  @type message :: %{role: String.t(), content: String.t()}
  @type option ::
          {:schema, map()}
          | {:user, String.t() | nil}
          | {:max_tokens, pos_integer()}
          | {:lane, atom()}
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
       busy_lanes: MapSet.new(),
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
      if :queue.len(state.queue) >= @max_queued do
        Logger.warning("Completion queue full (#{@max_queued}); rejecting topic=#{topic}")
        Phoenix.PubSub.broadcast(@pubsub, topic, {event, {:error, :queue_full}})
        state
      else
        dispatch(%{state | queue: :queue.in({topic, event, messages, opts}, state.queue)})
      end

    broadcast_status(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, :normal}, state) do
    new_state = state |> finished(ref) |> elem(1) |> dispatch()
    broadcast_status(new_state)
    {:noreply, new_state}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, reason}, state) do
    {info, state} = finished(state, ref)

    if info do
      {topic, event, _lane} = info
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
      new_state = dispatch(%{state | recently_failed: recently_failed})
      broadcast_status(new_state)
      {:noreply, new_state}
    else
      new_state = dispatch(state)
      broadcast_status(new_state)
      {:noreply, new_state}
    end
  end

  # Forget a finished completion and free its lane.
  defp finished(state, ref) do
    case Map.pop(state.monitors, ref) do
      {nil, _monitors} ->
        {nil, state}

      {{_topic, _event, lane} = info, monitors} ->
        {info,
         %{
           state
           | monitors: monitors,
             in_flight: map_size(monitors),
             busy_lanes: MapSet.delete(state.busy_lanes, lane)
         }}
    end
  end

  # Start queued completions while there are free slots and something queued
  # whose lane is free.
  defp dispatch(state) do
    with true <- state.in_flight < state.max_concurrent,
         {:ok, {topic, event, messages, opts}, queue} <-
           next_runnable(state.queue, state.busy_lanes) do
      ref = spawn_completion(topic, event, messages, opts)
      lane = opts[:lane]
      monitors = Map.put(state.monitors, ref, {topic, event, lane})

      dispatch(%{
        state
        | queue: queue,
          monitors: monitors,
          in_flight: map_size(monitors),
          busy_lanes: if(lane, do: MapSet.put(state.busy_lanes, lane), else: state.busy_lanes)
      })
    else
      _nothing_to_start -> state
    end
  end

  @doc false
  # The first queued completion that may start now: one with no lane, or whose
  # lane has nothing running. Everything else keeps its place. Public only so
  # the ordering can be tested.
  def next_runnable(queue, busy_lanes) do
    items = :queue.to_list(queue)

    case Enum.find_index(items, fn {_topic, _event, _messages, opts} ->
           opts[:lane] == nil or not MapSet.member?(busy_lanes, opts[:lane])
         end) do
      nil ->
        :none

      index ->
        {item, rest} = List.pop_at(items, index)
        {:ok, item, :queue.from_list(rest)}
    end
  end

  defp broadcast_status(state) do
    Phoenix.PubSub.broadcast(@pubsub, @status_topic, {:queue_status, build_status(state)})
  end

  defp build_status(state) do
    in_flight_items =
      Enum.map(Map.values(state.monitors), fn {topic, event, _lane} -> {topic, event} end)

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

  defp spawn_completion(topic, event, messages, opts) do
    {_pid, ref} =
      spawn_monitor(fn ->
        {result, thinking} = complete_sync(messages, opts)
        config = Settings.current()

        CompletionLog.record(
          topic,
          event,
          config[:model],
          config[:endpoint],
          messages,
          result,
          thinking
        )

        Events.record("ai.completion.finished",
          user: opts[:user],
          outcome: outcome(result),
          attributes: %{"ai.model" => config[:model], "ai.topic" => topic}
        )

        Phoenix.PubSub.broadcast(@pubsub, topic, {event, result})
      end)

    ref
  end

  defp outcome({:ok, _}), do: :ok
  defp outcome(_), do: :error

  @spec complete_sync([message()], [option()]) :: {result(), String.t() | nil}
  defp complete_sync(messages, opts) do
    if Application.get_env(:snow_se_tools, :mock_external_dependencies?, false) do
      mocked_completion(opts)
    else
      request_with_retry(messages, opts, @retries)
    end
  end

  defp request_with_retry(messages, opts, retries_left) do
    case request_completion(messages, opts) do
      {{:error, reason}, _thinking} = failed ->
        if retries_left > 0 and retryable?(reason) do
          Logger.warning("AI completion failed, retrying once: #{inspect(reason, limit: 5)}")
          Process.sleep(@retry_pause)
          request_with_retry(messages, opts, retries_left - 1)
        else
          failed
        end

      answered ->
        answered
    end
  end

  @doc false
  # Whether the server's error is worth one more try: a 5xx, or LM Studio's
  # 400 wrapping an engine fault ("Engine protocol predict stream returned an
  # error"), which covers its speculative-decoding batch fault and a context
  # window crowded by other requests. A plain 4xx (a bad request) is not, and
  # neither is a model that ran out of tokens -- it would again.
  def retryable?({status, _message}) when is_integer(status) and status >= 500, do: true

  def retryable?({400, message}) when is_binary(message),
    do: String.contains?(message, "Engine protocol predict stream returned an error")

  def retryable?(_reason), do: false

  defp mocked_completion(opts) do
    if opts[:schema] do
      {{:ok, %{}}, nil}
    else
      {{:ok, "Mock AI completion"}, nil}
    end
  end

  defp request_completion(messages, opts) do
    config = Settings.current()

    Logger.info(
      "AI completion: endpoint=#{config[:endpoint]} model=#{config[:model]} messages=#{length(messages)}"
    )

    body =
      %{model: config[:model], messages: messages}
      |> maybe_add_structured_output(opts[:schema])
      |> maybe_cap_output(opts[:max_tokens])

    case Req.post(config[:endpoint],
           json: body,
           headers: [{"authorization", "Bearer #{config[:api_key]}"}],
           receive_timeout: :timer.minutes(10)
         ) do
      {:ok, %{status: status, body: body}} ->
        interpret_response(status, body, opts[:schema])

      {:error, reason} ->
        {{:error, reason}, nil}
    end
  end

  @doc false
  # What the server's answer means, as `{result, thinking}`. Public only so the
  # parsing can be tested without a model to talk to.
  def interpret_response(200, body, schema),
    do: {extract_result(body, schema), extract_thinking(body)}

  def interpret_response(status, body, _schema),
    do: {{:error, {status, extract_error_message(body)}}, nil}

  # `finish_reason: "length"` means the model hit max_tokens. A thinking model
  # counts its reasoning against that budget, so it can spend all of it
  # thinking and come back with an empty answer -- which used to surface as
  # `{:invalid_json, ""}`, a parse error that hid what really happened.
  defp extract_result(
         %{"choices" => [%{"finish_reason" => "length", "message" => message} | _]} = body,
         schema
       ) do
    cond do
      String.trim(message_text(message)) == "" ->
        {:error, {:ran_out_of_tokens, :while_thinking}}

      is_nil(schema) ->
        # A plain-text answer that was cut short is still worth having.
        extract_content(body, schema)

      true ->
        case extract_content(body, schema) do
          {:ok, parsed} -> {:ok, parsed}
          {:error, _} -> {:error, {:ran_out_of_tokens, :mid_answer}}
        end
    end
  end

  defp extract_result(body, schema), do: extract_content(body, schema)

  defp message_text(%{"content" => content}) when is_binary(content), do: content

  defp message_text(%{"content" => blocks}) when is_list(blocks) do
    Enum.find_value(blocks, "", fn
      %{"type" => "text", "text" => t} when is_binary(t) -> t
      _ -> false
    end)
  end

  defp message_text(_message), do: ""

  # Without a ceiling a model with little to say can keep generating until it
  # fills the server's context window, which comes back as an opaque engine
  # error rather than as a completion. Callers that know roughly how long a
  # good answer is should say so.
  defp maybe_cap_output(body, nil), do: body

  defp maybe_cap_output(body, max_tokens) when is_integer(max_tokens) and max_tokens > 0,
    do: Map.put(body, :max_tokens, max_tokens)

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

  defp extract_error_message(%{"error" => %{"message" => msg}}) when is_binary(msg), do: msg
  defp extract_error_message(%{"error" => msg}) when is_binary(msg), do: msg

  # A server (or a proxy in front of it) that fails before reaching the model
  # often answers with an HTML error page. Keep the words, not the markup.
  defp extract_error_message(body) when is_binary(body) do
    text =
      if body =~ ~r/<(!doctype|html|body|pre)\b/i do
        body
        |> String.replace(~r/<head\b.*?<\/head>/is, " ")
        |> String.replace(~r/<[^>]*>/s, " ")
        |> String.replace(~r/\s+/, " ")
        |> String.trim()
      else
        String.trim(body)
      end

    cond do
      text == "" -> "(no message)"
      String.length(text) > 300 -> String.slice(text, 0, 300) <> "…"
      true -> text
    end
  end

  defp extract_error_message(body), do: inspect(body, limit: 10, printable_limit: 300)
end
