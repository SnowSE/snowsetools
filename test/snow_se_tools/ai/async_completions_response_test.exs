defmodule SnowSeTools.AI.AsyncCompletionsResponseTest do
  use ExUnit.Case, async: true

  alias SnowSeTools.AI.AsyncCompletions
  alias SnowSeTools.Curriculum.CurriculumDomainManager

  @schema %{"type" => "object"}

  defp choice(finish_reason, content, reasoning \\ "") do
    %{
      "choices" => [
        %{
          "finish_reason" => finish_reason,
          "message" => %{"content" => content, "reasoning_content" => reasoning}
        }
      ]
    }
  end

  describe "a thinking model that hits max_tokens" do
    # The shape LM Studio returned for qwen3.8 when its reasoning used the
    # whole budget: finish_reason "length", empty content.
    test "with nothing written is reported as running out while thinking" do
      body = choice("length", "", "Let me consider each outcome in turn...")

      assert {{:error, {:ran_out_of_tokens, :while_thinking}}, "Let me consider" <> _} =
               AsyncCompletions.interpret_response(200, body, @schema)
    end

    test "partway through a structured answer is reported as cut off" do
      body = choice("length", ~s({"skills": [{"skill": "Debug))

      assert {{:error, {:ran_out_of_tokens, :mid_answer}}, _} =
               AsyncCompletions.interpret_response(200, body, @schema)
    end

    test "with plain text written keeps the text it got" do
      body = choice("length", "A partial summary")

      assert {{:ok, "A partial summary"}, _} =
               AsyncCompletions.interpret_response(200, body, nil)
    end
  end

  test "a finished structured answer still parses" do
    body = choice("stop", ~s({"skills": []}))

    assert {{:ok, %{"skills" => []}}, _} =
             AsyncCompletions.interpret_response(200, body, @schema)
  end

  test "malformed JSON from a finished answer is still a parse error" do
    assert {{:error, {:invalid_json, "nope"}}, _} =
             AsyncCompletions.interpret_response(200, choice("stop", "nope"), @schema)
  end

  describe "error status" do
    test "an HTML error page is reduced to its words" do
      html = """
      <!DOCTYPE html>
      <html lang="en">
      <head>
      <meta charset="utf-8">
      <title>Error</title>
      </head>
      <body>
      <pre>Internal Server Error</pre>
      </body>
      </html>
      """

      assert {{:error, {500, "Internal Server Error"}}, nil} =
               AsyncCompletions.interpret_response(500, html, @schema)
    end

    test "an OpenAI-style error object gives its message" do
      body = %{"error" => %{"message" => "Model is loading"}}

      assert {{:error, {503, "Model is loading"}}, nil} =
               AsyncCompletions.interpret_response(503, body, @schema)
    end

    test "a bare error string is used as is" do
      assert {{:error, {400, "No models loaded"}}, nil} =
               AsyncCompletions.interpret_response(400, %{"error" => "No models loaded"}, nil)
    end
  end

  describe "how the curriculum page words these" do
    test "running out while thinking says so plainly" do
      message = CurriculumDomainManager.format_reason({:ran_out_of_tokens, :while_thinking})
      assert message =~ "whole token budget thinking"
    end

    test "a server error message is not wrapped in quotes" do
      assert CurriculumDomainManager.format_reason({500, "Internal Server Error"}) ==
               "AI service answered 500: Internal Server Error"
    end
  end
end
