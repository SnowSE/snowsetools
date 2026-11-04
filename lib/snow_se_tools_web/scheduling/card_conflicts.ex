defmodule SnowSeToolsWeb.Scheduling.CardConflicts do
  @moduledoc """
  The conflicts a schedule card should own up to, indexed so each card can
  find its own quickly: by owner key for a professor or room, and by CRN for a
  program semester option (whose sections are any of the term's).

  Built from what the conflicts panel shows -- detected and not acknowledged --
  plus the active change group's conflicts. `checked?` stays false until the
  term's conflicts have actually come back, so a card never says "no
  conflicts" before anyone has looked.
  """

  alias SnowSeToolsWeb.Scheduling.ScheduleConflictDetail

  defstruct by_crn: %{}, by_owner_key: %{}, checked?: false

  @type t :: %__MODULE__{
          by_crn: %{optional(String.t()) => [map()]},
          by_owner_key: %{optional(String.t()) => [map()]},
          checked?: boolean()
        }

  def new(conflicts, checked?: checked?) do
    conflicts = Enum.uniq_by(conflicts, &identity/1)

    %__MODULE__{
      by_crn: index(conflicts, &value(&1, :course_crns)),
      by_owner_key: index(conflicts, &value(&1, :owner_keys)),
      checked?: checked?
    }
  end

  def merge(%__MODULE__{} = left, %__MODULE__{} = right) do
    %__MODULE__{
      by_crn: Map.merge(left.by_crn, right.by_crn, fn _crn, a, b -> a ++ b end),
      by_owner_key: Map.merge(left.by_owner_key, right.by_owner_key, fn _key, a, b -> a ++ b end),
      checked?: left.checked? or right.checked?
    }
  end

  def for_owner(%__MODULE__{by_owner_key: by_owner_key}, owner_key),
    do: by_owner_key |> Map.get(owner_key, []) |> Enum.uniq_by(&identity/1)

  def for_crns(%__MODULE__{by_crn: by_crn}, crns) do
    crns
    |> Enum.flat_map(&Map.get(by_crn, &1, []))
    |> Enum.uniq_by(&identity/1)
  end

  def any_for_crns?(%__MODULE__{by_crn: by_crn}, crns),
    do: Enum.any?(crns, &Map.has_key?(by_crn, &1))

  @doc ~S"One line per conflict: what kind, over what, which classes, when."
  def summary(conflict) do
    heading =
      case to_string(value(conflict, :type)) do
        "overlap" -> "Classes at the same time"
        "room" -> "Room: #{value(conflict, :resource_label)}"
        "professor" -> "Professor: #{value(conflict, :resource_label)}"
        _other -> "Conflict"
      end

    online =
      case value(conflict, :online_alternatives) do
        [_ | _] = sections -> "Online instead: #{Enum.join(sections, ", ")}"
        _none -> nil
      end

    %{
      heading: heading,
      courses: Enum.join(ScheduleConflictDetail.course_labels(conflict), " · "),
      when: ScheduleConflictDetail.overlap_when(conflict),
      online: online
    }
  end

  defp index(conflicts, keys_fun) do
    Enum.reduce(conflicts, %{}, fn conflict, acc ->
      conflict
      |> keys_fun.()
      |> List.wrap()
      |> Enum.reduce(acc, fn key, key_acc ->
        Map.update(key_acc, key, [conflict], &[conflict | &1])
      end)
    end)
    |> Map.new(fn {key, list} -> {key, Enum.reverse(list)} end)
  end

  # The same clash can come from the term and from the active change group.
  defp identity(conflict) do
    value(conflict, :fingerprint) ||
      {value(conflict, :type), value(conflict, :resource_label), value(conflict, :course_crns)}
  end

  defp value(conflict, key), do: Map.get(conflict, key, Map.get(conflict, Atom.to_string(key)))
end
