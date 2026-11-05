defmodule SnowSeTools.AI.ConnectionTest do
  @moduledoc """
  Asks an AI server for a one-word reply, to show an admin whether an
  endpoint, model and key work before anything depends on them.

  It goes straight to the server rather than through `AsyncCompletions`: the
  queue can be busy with curriculum reviews that take minutes each, and a test
  that waits behind them answers the wrong question.
  """

  require Logger

  alias SnowSeTools.AI.AsyncCompletions
  alias SnowSeTools.Data.Text

  @prompt [%{role: "user", content: "Reply with the single word: ok"}]
  # A thinking model reasons before it answers, so the budget allows some of
  # that; running out of it still proves the server and model are working.
  @max_tokens 256
  @timeout :timer.seconds(60)

  @type outcome :: %{
          endpoint: String.t() | nil,
          model: String.t() | nil,
          elapsed_ms: non_neg_integer(),
          message: String.t()
        }

  @spec run(endpoint: String.t() | nil, model: String.t() | nil, api_key: String.t() | nil) ::
          {:ok, outcome()} | {:error, outcome()}
  def run(endpoint: endpoint, model: model, api_key: api_key) do
    started = System.monotonic_time(:millisecond)
    result = request(endpoint: endpoint, model: model, api_key: api_key)

    outcome = %{
      endpoint: endpoint,
      model: model,
      elapsed_ms: System.monotonic_time(:millisecond) - started
    }

    case result do
      {:ok, reply} ->
        {:ok, Map.put(outcome, :message, reply)}

      {:error, reason} ->
        Logger.warning(
          "AI connection test failed: endpoint=#{endpoint} model=#{model} reason=#{inspect(reason)}"
        )

        {:error, Map.put(outcome, :message, describe(reason))}
    end
  end

  defp request(endpoint: endpoint, model: model, api_key: api_key) do
    cond do
      Text.blank?(endpoint) ->
        {:error, :no_endpoint}

      Text.blank?(model) ->
        {:error, :no_model}

      Application.get_env(:snow_se_tools, :mock_external_dependencies?, false) ->
        {:ok, "Replied “ok”"}

      true ->
        post(endpoint: endpoint, model: model, api_key: api_key)
    end
  end

  defp post(endpoint: endpoint, model: model, api_key: api_key) do
    response =
      Req.post(endpoint,
        json: %{model: model, messages: @prompt, max_tokens: @max_tokens},
        headers: [{"authorization", "Bearer #{api_key}"}],
        receive_timeout: @timeout,
        retry: false
      )

    case response do
      {:ok, %{status: status, body: body}} ->
        {result, _thinking} = AsyncCompletions.interpret_response(status, body, nil)
        answered(result)

      {:error, reason} ->
        {:error, reason}
    end
  rescue
    exception -> {:error, {:exception, Exception.message(exception)}}
  end

  defp answered({:ok, reply}) when is_binary(reply), do: {:ok, "Replied “#{String.trim(reply)}”"}

  defp answered({:error, {:ran_out_of_tokens, _where}}),
    do: {:ok, "Answered, but used up the test's #{@max_tokens}-token budget thinking"}

  defp answered({:error, reason}), do: {:error, reason}

  defp describe(:no_endpoint), do: "No endpoint is set."
  defp describe(:no_model), do: "No model is set."
  defp describe({status, message}) when is_integer(status), do: "HTTP #{status}: #{message}"
  defp describe({:exception, message}), do: message
  defp describe(exception) when is_exception(exception), do: Exception.message(exception)
  defp describe(reason), do: inspect(reason)
end
