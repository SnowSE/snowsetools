defmodule SimpleSyllabusReporter.Reports.RequiredReportElementCoverageCache do
  use GenServer
  require Logger

  alias SimpleSyllabusReporter.Reports.GeneratedReportItem

  @pubsub SimpleSyllabusReporter.PubSub

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, %{counts: %{}, syllabi_codes: []}, name: __MODULE__)
  end

  def topic(element_id), do: "element_coverage:#{element_id}"

  def get(element_id) do
    GenServer.call(__MODULE__, {:get, element_id})
  end

  def subscribe(element_id) do
    Phoenix.PubSub.subscribe(@pubsub, topic(element_id))
  end

  def unsubscribe(element_id) do
    Phoenix.PubSub.unsubscribe(@pubsub, topic(element_id))
  end

  def notify_item_saved(element_id) do
    GenServer.cast(__MODULE__, {:refresh, element_id})
  end

  def set_syllabi_codes(codes) when is_list(codes) do
    GenServer.cast(__MODULE__, {:set_syllabi_codes, codes})
  end

  def get_syllabi_codes do
    GenServer.call(__MODULE__, :get_syllabi_codes)
  end

  @impl true
  def init(state) do
    send(self(), :hydrate)
    {:ok, state}
  end

  @impl true
  def handle_call({:get, element_id}, _from, state) do
    counts = Map.get(state.counts, element_id)
    {:reply, with_not_generated(counts, length(state.syllabi_codes)), state}
  end

  @impl true
  def handle_call(:get_syllabi_codes, _from, state) do
    {:reply, state.syllabi_codes, state}
  end

  @impl true
  def handle_cast({:set_syllabi_codes, codes}, state) do
    {:noreply, %{state | syllabi_codes: codes}}
  end

  @impl true
  def handle_cast({:refresh, element_id}, state) do
    state =
      case GeneratedReportItem.item_counts_for_element(element_id) do
        {:ok, raw} ->
          counts = Map.put(state.counts, element_id, raw)
          broadcast(element_id, with_not_generated(raw, length(state.syllabi_codes)))
          %{state | counts: counts}

        {:error, reason} ->
          Logger.error(
            "RequiredReportElementCoverageCache refresh failed element_id=#{element_id} reason=#{inspect(reason)}"
          )

          state
      end

    {:noreply, state}
  end

  @impl true
  def handle_info(:hydrate, state) do
    counts =
      case GeneratedReportItem.all_element_coverage_counts() do
        {:ok, rows} ->
          Map.new(rows, fn row ->
            {row["element_id"],
             %{
               "met" => row["met"],
               "not_met" => row["not_met"],
               "partially_met" => row["partially_met"]
             }}
          end)

        {:error, reason} ->
          Logger.error("RequiredReportElementCoverageCache hydration failed: #{inspect(reason)}")
          %{}
      end

    {:noreply, %{state | counts: counts}}
  end

  defp with_not_generated(nil, _total), do: nil

  defp with_not_generated(counts, total_syllabi) do
    generated = counts["met"] + counts["not_met"] + counts["partially_met"]
    not_generated = max(0, total_syllabi - generated)
    Map.merge(counts, %{"not_generated" => not_generated, "total_syllabi" => total_syllabi})
  end

  defp broadcast(element_id, counts) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      topic(element_id),
      {:element_coverage_updated, element_id, counts}
    )
  end
end
