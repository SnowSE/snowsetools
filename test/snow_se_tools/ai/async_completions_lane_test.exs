defmodule SnowSeTools.AI.AsyncCompletionsLaneTest do
  # The AI server shares one context window among the requests it runs at
  # once, so big prompts (curriculum reviews) go one at a time in a lane, and
  # the server's one-off engine faults get a second try.
  use ExUnit.Case, async: false

  alias SnowSeTools.AI.AsyncCompletions

  describe "which queued completion starts next" do
    test "the first one, when nothing is in its lane" do
      queue = queue([item(:a, :review), item(:b, nil)])

      assert {:ok, {_, :a, _, _}, rest} = AsyncCompletions.next_runnable(queue, MapSet.new())
      assert names(rest) == [:b]
    end

    test "skips past a busy lane without losing anyone's place" do
      queue = queue([item(:a, :review), item(:b, :review), item(:c, nil), item(:d, :other)])

      assert {:ok, {_, :c, _, _}, rest} =
               AsyncCompletions.next_runnable(queue, MapSet.new([:review]))

      assert names(rest) == [:a, :b, :d]
    end

    test "nothing, when every queued completion's lane is busy" do
      queue = queue([item(:a, :review), item(:b, :review)])
      assert AsyncCompletions.next_runnable(queue, MapSet.new([:review])) == :none
    end

    test "a lane's completions start in the order they were asked for" do
      queue = queue([item(:first, :review), item(:second, :review)])
      assert {:ok, {_, :first, _, _}, _rest} = AsyncCompletions.next_runnable(queue, MapSet.new())
    end
  end

  describe "which errors are tried again" do
    test "LM Studio's engine faults, which it reports as a 400" do
      for message <- [
            ~s|Engine protocol predict stream returned an error: {"code":500,"message":"got exception: speculative batch index 8 is not inside the current sub-batch [0, 8)"}|,
            ~s|Engine protocol predict stream returned an error: {"code":500,"message":"Context size has been exceeded."}|
          ] do
        assert AsyncCompletions.retryable?({400, message})
      end
    end

    test "any 5xx" do
      assert AsyncCompletions.retryable?({500, "Internal Server Error"})
      assert AsyncCompletions.retryable?({503, "Service Unavailable"})
    end

    test "not a bad request, and not running out of tokens" do
      refute AsyncCompletions.retryable?({400, "'messages' must be an array"})
      refute AsyncCompletions.retryable?({401, "Unauthorized"})
      refute AsyncCompletions.retryable?({:ran_out_of_tokens, :mid_answer})
      refute AsyncCompletions.retryable?(%Req.TransportError{reason: :timeout})
    end
  end

  test "a burst of laned and unlaned completions all finish" do
    topic = "lane-test-#{System.unique_integer([:positive])}"
    Phoenix.PubSub.subscribe(SnowSeTools.PubSub, topic)

    for n <- 1..6, do: AsyncCompletions.complete(topic, {:review, n}, [], lane: :lane_test)
    for n <- 1..3, do: AsyncCompletions.complete(topic, {:other, n}, [])

    for n <- 1..6, do: assert_receive({{:review, ^n}, {:ok, _}}, 5_000)
    for n <- 1..3, do: assert_receive({{:other, ^n}, {:ok, _}}, 5_000)

    status = AsyncCompletions.status()
    refute Enum.any?(status.in_flight_items ++ status.queued_items, &match?({^topic, _}, &1))
  end

  defp item(name, lane), do: {"topic", name, [], if(lane, do: [lane: lane], else: [])}
  defp queue(items), do: :queue.from_list(items)
  defp names(queue), do: queue |> :queue.to_list() |> Enum.map(&elem(&1, 1))
end
