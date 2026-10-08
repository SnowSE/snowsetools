defmodule SnowSeTools.Curriculum.SuggestionDecisions do
  @moduledoc """
  What accepting a suggestion does to the map. Each acceptance runs in one
  transaction with marking the suggestion accepted, so a failure leaves both
  the map and the suggestion as they were.
  """

  alias SnowSeTools.Curriculum.{CurriculumDb, SkillDb, SuggestionBuilder, SuggestionDb}
  alias SnowSeTools.Data.DbHelpers

  @doc """
  Applies the suggestion. `level` overrides the suggested level of a
  course–skill link, for an editor who agrees with the link but not the level.
  """
  def accept(suggestion: suggestion, decided_by: decided_by, level: level) do
    DbHelpers.transaction(fn ->
      with :ok <- apply_suggestion(suggestion, decided_by: decided_by, level: level) do
        SuggestionDb.decide(id: suggestion["id"], status: "accepted", decided_by: decided_by)
      end
    end)
  end

  def reject(suggestion: suggestion, decided_by: decided_by) do
    SuggestionDb.decide(id: suggestion["id"], status: "rejected", decided_by: decided_by)
  end

  defp apply_suggestion(%{"kind" => "course_skill"} = suggestion,
         decided_by: decided_by,
         level: level
       ) do
    payload = suggestion["payload"]
    level = if level in CurriculumDb.levels(), do: level, else: payload["level"]

    with {:ok, skill} <- find_or_create_skill(payload) do
      SkillDb.set_course_skill(
        subject_code: suggestion["subject_code"],
        course_number: suggestion["course_number"],
        skill_id: skill["id"],
        level: level,
        note: suggestion["evidence"],
        updated_by: decided_by
      )
    end
  end

  defp apply_suggestion(%{"kind" => "skill_dependency", "payload" => payload}, _opts) do
    with {:ok, skill} <- existing_skill(payload["skill_name"]),
         {:ok, builds_on} <- existing_skill(payload["builds_on_name"]) do
      SkillDb.add_dependency(skill_id: skill["id"], builds_on_skill_id: builds_on["id"])
    end
  end

  defp apply_suggestion(%{"kind" => "merge_skills", "payload" => payload} = suggestion, _opts) do
    keep_name = payload["keep_name"]
    merge_name = payload["merge_name"]

    with :ok <- merge_in_catalog(keep_name, merge_name) do
      rename_in_pending(from: merge_name, to: keep_name, except: suggestion["id"])
    end
  end

  # The duplicate may only exist as a name some pending suggestions propose;
  # then there is nothing to change in the catalog itself.
  defp merge_in_catalog(keep_name, merge_name) do
    case {SkillDb.find_skill_by_name(keep_name), SkillDb.find_skill_by_name(merge_name)} do
      {{:ok, keep}, {:ok, duplicate}} ->
        SkillDb.merge_skills(keep_id: keep["id"], merge_id: duplicate["id"])

      {{:error, :not_found}, {:ok, duplicate}} ->
        with {:ok, _renamed} <-
               SkillDb.update_skill(
                 id: duplicate["id"],
                 name: keep_name,
                 category: duplicate["category"],
                 description: duplicate["description"]
               ),
             do: :ok

      {_keep, {:error, :not_found}} ->
        :ok

      {{:error, reason}, _duplicate} ->
        {:error, reason}

      {_keep, {:error, reason}} ->
        {:error, reason}
    end
  end

  # After "Git CLI" is merged into "Git (command line)", every pending
  # suggestion that names "Git CLI" now means the kept skill. A suggestion that
  # becomes a duplicate of another, or a skill building on itself, has nothing
  # left to ask and is retired.
  defp rename_in_pending(from: from, to: to, except: except_id) do
    with {:ok, pending} <- SuggestionDb.list_pending() do
      pending
      |> Enum.reject(&(&1["id"] == except_id))
      |> Enum.map(&{&1, rename_payload(&1, from, to)})
      |> Enum.reduce_while({:ok, MapSet.new()}, fn {original, renamed}, {:ok, seen} ->
        fingerprint = SuggestionBuilder.fingerprint(renamed)

        result =
          cond do
            pointless?(renamed) or MapSet.member?(seen, fingerprint) ->
              SuggestionDb.mark_superseded(original["id"])

            renamed["payload"] == original["payload"] ->
              :ok

            true ->
              SuggestionDb.update_payload(
                id: original["id"],
                payload: renamed["payload"],
                fingerprint: fingerprint
              )
          end

        case result do
          :ok -> {:cont, {:ok, MapSet.put(seen, fingerprint)}}
          {:error, reason} -> {:halt, {:error, reason}}
        end
      end)
      |> case do
        {:ok, _seen} -> :ok
        {:error, reason} -> {:error, reason}
      end
    end
  end

  defp rename_payload(suggestion, from, to) do
    from_key = SuggestionBuilder.key(from)

    payload =
      Map.new(suggestion["payload"], fn {field, value} ->
        if field in ["skill_name", "builds_on_name", "keep_name", "merge_name"] and
             SuggestionBuilder.key(value) == from_key do
          {field, to}
        else
          {field, value}
        end
      end)

    payload =
      if suggestion["kind"] == "course_skill" and payload != suggestion["payload"],
        do: Map.put(payload, "skill_id", nil),
        else: payload

    %{suggestion | "payload" => payload}
  end

  defp pointless?(%{"kind" => "skill_dependency", "payload" => payload}),
    do:
      SuggestionBuilder.key(payload["skill_name"]) ==
        SuggestionBuilder.key(payload["builds_on_name"])

  defp pointless?(%{"kind" => "merge_skills", "payload" => payload}),
    do:
      SuggestionBuilder.key(payload["keep_name"]) == SuggestionBuilder.key(payload["merge_name"])

  defp pointless?(_suggestion), do: false

  defp find_or_create_skill(payload) do
    case SkillDb.find_skill_by_name(payload["skill_name"]) do
      {:ok, skill} ->
        {:ok, skill}

      {:error, :not_found} ->
        SkillDb.create_skill(
          name: payload["skill_name"],
          category: payload["category"],
          description: payload["description"]
        )

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp existing_skill(name) do
    case SkillDb.find_skill_by_name(name) do
      {:ok, skill} ->
        {:ok, skill}

      {:error, :not_found} ->
        {:error, "Add the skill \"#{name}\" first (accept its suggestion), then this link."}

      {:error, reason} ->
        {:error, reason}
    end
  end
end
