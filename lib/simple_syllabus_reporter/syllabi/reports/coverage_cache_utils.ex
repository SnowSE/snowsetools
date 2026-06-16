defmodule SimpleSyllabusReporter.Reports.CoverageCacheUtils do
  @moduledoc """
  Pure utility functions for element coverage cache logic.
  No state, no GenServer — used by ReportGeneratorDomainManger.
  """

  alias SimpleSyllabusReporter.Syllabi.SyllabusDB

  @pubsub SimpleSyllabusReporter.PubSub

  def element_topic(element_id), do: "element_coverage:#{element_id}"

  def broadcast_element(element_id, counts) do
    Phoenix.PubSub.broadcast(
      @pubsub,
      element_topic(element_id),
      {:element_coverage_updated, element_id, counts}
    )
  end

  def with_not_generated(nil), do: nil

  def with_not_generated(counts) do
    total_syllabi = counts["total_syllabi"] || 0
    generated = counts["met"] + counts["not_met"] + counts["partially_met"]
    not_generated = max(0, total_syllabi - generated)
    Map.put(counts, "not_generated", not_generated)
  end

  def hydrate_counts(rows) do
    Map.new(rows, fn row ->
      {row["element_id"],
       %{
         "met" => row["met"],
         "not_met" => row["not_met"],
         "partially_met" => row["partially_met"],
         "total_syllabi" => row["total_syllabi"]
       }}
    end)
  end

  def aggregate_totals(counts) do
    item_totals =
      Enum.reduce(
        counts,
        %{"met" => 0, "not_met" => 0, "partially_met" => 0, "syllabi_with_reports" => 0},
        fn {_element_id, c}, acc ->
          %{
            "met" => acc["met"] + c["met"],
            "not_met" => acc["not_met"] + c["not_met"],
            "partially_met" => acc["partially_met"] + c["partially_met"],
            "syllabi_with_reports" => max(acc["syllabi_with_reports"], c["total_syllabi"] || 0)
          }
        end
      )

    total_syllabi =
      case SyllabusDB.count_in_scope() do
        {:ok, n} -> n
        _ -> item_totals["syllabi_with_reports"]
      end

    item_totals
    |> Map.put("total_syllabi", total_syllabi)
    |> Map.put("not_generated", max(0, total_syllabi - item_totals["syllabi_with_reports"]))
  end
end
