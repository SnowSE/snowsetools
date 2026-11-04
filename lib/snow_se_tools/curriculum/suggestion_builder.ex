defmodule SnowSeTools.Curriculum.SuggestionBuilder do
  @moduledoc """
  Turns what the model answered into suggestions an editor can act on, and
  drops what would not change anything: a link the map already has at that
  level, a "builds on" edge already drawn, or anything an editor rejected
  before.

  `state` is the map as it stands:

      %{skills: [skill], links: [link], dependencies: [dep], rejected: MapSet}
  """

  alias SnowSeTools.Curriculum.CurriculumDb

  @max_name_length 80

  def from_course_review(answer: result, course: course, state: state) when is_map(result) do
    index = index(state)
    subject = course["subject_code"]
    number = course["course_number"]

    skill_suggestions =
      result
      |> list("skills")
      |> Enum.flat_map(&course_skill(&1, subject, number, index))

    proposed =
      Map.new(skill_suggestions, &{key(&1["payload"]["skill_name"]), &1["payload"]["skill_name"]})

    dependency_suggestions =
      result
      |> list("builds_on")
      |> Enum.flat_map(&dependency(&1, index, proposed))

    (skill_suggestions ++ dependency_suggestions)
    |> Enum.reject(&MapSet.member?(state.rejected, &1["fingerprint"]))
    |> Enum.uniq_by(& &1["fingerprint"])
  end

  def from_course_review(answer: _not_a_map, course: _course, state: _state), do: []

  @doc """
  Merge suggestions from the end-of-run pass. Both names must be known —
  in the catalog or proposed by this run — so a name the model invented in
  the merge pass itself is ignored.
  """
  def from_merge_review(answer: result, proposed_names: proposed_names, state: state)
      when is_map(result) do
    index = index(state)
    proposed = Map.new(proposed_names, &{key(&1), &1})

    result
    |> list("merges")
    |> Enum.flat_map(fn merge ->
      keep = resolve(merge["keep"], index, proposed)
      duplicate = resolve(merge["merge"], index, proposed)

      if keep && duplicate && key(keep) != key(duplicate) do
        [
          %{
            "kind" => "merge_skills",
            "subject_code" => nil,
            "course_number" => nil,
            "payload" => %{"keep_name" => keep, "merge_name" => duplicate},
            "fingerprint" => "merge_skills|#{key(keep)}|#{key(duplicate)}",
            "rationale" => text(merge["rationale"]),
            "evidence" => ""
          }
        ]
      else
        []
      end
    end)
    |> Enum.reject(&MapSet.member?(state.rejected, &1["fingerprint"]))
    |> Enum.uniq_by(& &1["fingerprint"])
  end

  def from_merge_review(answer: _not_a_map, proposed_names: _names, state: _state), do: []

  @doc "What a suggestion proposes, as a stable string; see `SuggestionDb`."
  def fingerprint(%{"kind" => "course_skill"} = suggestion) do
    payload = suggestion["payload"]

    "course_skill|#{suggestion["subject_code"]}|#{suggestion["course_number"]}|" <>
      "#{key(payload["skill_name"])}|#{payload["level"]}"
  end

  def fingerprint(%{"kind" => "skill_dependency", "payload" => payload}),
    do: "skill_dependency|#{key(payload["skill_name"])}|#{key(payload["builds_on_name"])}"

  def fingerprint(%{"kind" => "merge_skills", "payload" => payload}),
    do: "merge_skills|#{key(payload["keep_name"])}|#{key(payload["merge_name"])}"

  def key(name) when is_binary(name), do: name |> String.trim() |> String.downcase()
  def key(_name), do: ""

  defp course_skill(item, subject, number, index) do
    name = clean_name(item["name"])
    level = item["level"]

    existing = name && Map.get(index.skills, key(name))
    current_level = existing && Map.get(index.links, {subject, number, existing["id"]})

    cond do
      name == nil or level not in CurriculumDb.levels() ->
        []

      current_level == level ->
        []

      true ->
        suggestion = %{
          "kind" => "course_skill",
          "subject_code" => subject,
          "course_number" => number,
          "payload" => %{
            "skill_name" => (existing && existing["name"]) || name,
            "skill_id" => existing && existing["id"],
            "category" => category((existing && existing["category"]) || item["category"]),
            "description" => (existing && existing["description"]) || text(item["description"]),
            "level" => level,
            "current_level" => current_level,
            "source" => text(item["source"])
          },
          "rationale" => "",
          "evidence" => text(item["evidence"])
        }

        [Map.put(suggestion, "fingerprint", fingerprint(suggestion))]
    end
  end

  defp dependency(item, index, proposed) do
    skill = resolve(item["skill"], index, proposed)
    builds_on = resolve(item["builds_on"], index, proposed)

    cond do
      skill == nil or builds_on == nil or key(skill) == key(builds_on) ->
        []

      already_drawn?(skill, builds_on, index) ->
        []

      true ->
        suggestion = %{
          "kind" => "skill_dependency",
          "subject_code" => nil,
          "course_number" => nil,
          "payload" => %{"skill_name" => skill, "builds_on_name" => builds_on},
          "rationale" => text(item["rationale"]),
          "evidence" => ""
        }

        [Map.put(suggestion, "fingerprint", fingerprint(suggestion))]
    end
  end

  defp already_drawn?(skill, builds_on, index) do
    with %{"id" => skill_id} <- Map.get(index.skills, key(skill)),
         %{"id" => builds_on_id} <- Map.get(index.skills, key(builds_on)) do
      MapSet.member?(index.dependencies, {skill_id, builds_on_id})
    else
      _not_both_in_catalog -> false
    end
  end

  defp resolve(name, index, proposed) do
    case clean_name(name) do
      nil ->
        nil

      clean ->
        case Map.get(index.skills, key(clean)) do
          %{"name" => catalog_name} -> catalog_name
          nil -> Map.get(proposed, key(clean))
        end
    end
  end

  defp index(state) do
    %{
      skills: Map.new(state.skills, &{key(&1["name"]), &1}),
      links:
        Map.new(
          state.links,
          &{{&1["subject_code"], &1["course_number"], &1["skill_id"]}, &1["level"]}
        ),
      dependencies: MapSet.new(state.dependencies, &{&1["skill_id"], &1["builds_on_skill_id"]})
    }
  end

  defp clean_name(name) when is_binary(name) do
    case name |> String.trim() |> String.replace(~r/\s+/, " ") do
      "" -> nil
      clean -> String.slice(clean, 0, @max_name_length)
    end
  end

  defp clean_name(_name), do: nil

  defp category(value) do
    if value in CurriculumDb.skill_categories(), do: value, else: "concept"
  end

  defp list(result, field) do
    case Map.get(result, field) do
      items when is_list(items) -> Enum.filter(items, &is_map/1)
      _missing -> []
    end
  end

  defp text(value) when is_binary(value), do: String.trim(value)
  defp text(_value), do: ""
end
