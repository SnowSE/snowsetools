defmodule SnowSeToolsWeb.Scheduling.ScheduleOverlays do
  @moduledoc """
  Pure data for overlay groups: a group is a set of same-kind schedule owners
  drawn on one week grid, each in its own color.

  Group keys live in the same `ScheduleOrder` as solo owner keys, prefixed with
  `"overlay:"`, so cards and groups can be reordered together. Member owner keys
  are *not* in the order while they belong to a group.
  """

  @group_prefix "overlay:"

  defstruct groups: %{}

  @type owner_key :: String.t()
  @type group_key :: String.t()
  @type t :: %__MODULE__{groups: %{optional(group_key()) => [owner_key()]}}

  # Colors for members inside an overlay. Rose/emerald/amber are deliberately
  # excluded: the grid already uses them for conflicted/added/updated courses.
  @member_colors [
    %{name: "sky", block: "bg-sky-950/60 ring-1 ring-sky-400/60", dot: "bg-sky-400"},
    %{name: "violet", block: "bg-violet-950/60 ring-1 ring-violet-400/60", dot: "bg-violet-400"},
    %{name: "orange", block: "bg-orange-950/60 ring-1 ring-orange-400/60", dot: "bg-orange-400"},
    %{name: "lime", block: "bg-lime-950/60 ring-1 ring-lime-400/60", dot: "bg-lime-400"},
    %{
      name: "fuchsia",
      block: "bg-fuchsia-950/60 ring-1 ring-fuchsia-400/60",
      dot: "bg-fuchsia-400"
    },
    %{name: "cyan", block: "bg-cyan-950/60 ring-1 ring-cyan-400/60", dot: "bg-cyan-400"}
  ]

  # Button color per owner kind, so it is visible at a glance which cards can
  # combine: people with people, rooms with rooms.
  @kind_styles %{
    professor: %{
      label: "people",
      singular: "person",
      button:
        "border-indigo-400/60 bg-indigo-500/15 text-indigo-200 hover:bg-indigo-500/25 hover:text-indigo-100"
    },
    room: %{
      label: "rooms",
      singular: "room",
      button:
        "border-teal-400/60 bg-teal-500/15 text-teal-200 hover:bg-teal-500/25 hover:text-teal-100"
    },
    academic_program_semester: %{
      label: "program semesters",
      singular: "program semester",
      button:
        "border-purple-400/60 bg-purple-500/15 text-purple-200 hover:bg-purple-500/25 hover:text-purple-100"
    }
  }

  def new, do: %__MODULE__{}

  def group_key?(key) when is_binary(key), do: String.starts_with?(key, @group_prefix)
  def group_key?(_key), do: false

  def group_keys(%__MODULE__{groups: groups}), do: Map.keys(groups)

  def members(overlays: %__MODULE__{groups: groups}, group_key: group_key),
    do: Map.get(groups, group_key, [])

  def all_owner_keys(%__MODULE__{groups: groups}), do: groups |> Map.values() |> List.flatten()

  @doc "The group an owner belongs to, or nil."
  def owner_group(overlays: %__MODULE__{groups: groups}, owner_key: owner_key) do
    Enum.find_value(groups, fn {group_key, members} ->
      if owner_key in members, do: group_key
    end)
  end

  @doc "Creates a group from the given owner keys. Returns `{group_key, overlays}`."
  def create(overlays: %__MODULE__{} = overlays, owner_keys: owner_keys)
      when is_list(owner_keys) do
    group_key = @group_prefix <> Integer.to_string(:erlang.unique_integer([:positive]))
    {group_key, %{overlays | groups: Map.put(overlays.groups, group_key, Enum.uniq(owner_keys))}}
  end

  def add_member(overlays: %__MODULE__{} = overlays, group_key: group_key, owner_key: owner_key) do
    %{
      overlays
      | groups:
          Map.update(overlays.groups, group_key, [owner_key], fn members ->
            if owner_key in members, do: members, else: members ++ [owner_key]
          end)
    }
  end

  def remove_member(
        overlays: %__MODULE__{} = overlays,
        group_key: group_key,
        owner_key: owner_key
      ) do
    case Map.get(overlays.groups, group_key) do
      nil -> overlays
      members -> %{overlays | groups: Map.put(overlays.groups, group_key, members -- [owner_key])}
    end
  end

  def delete_group(overlays: %__MODULE__{} = overlays, group_key: group_key) do
    %{overlays | groups: Map.delete(overlays.groups, group_key)}
  end

  @doc "Drops any member not in `keys`; groups left with no members are removed."
  def retain_owner_keys(overlays: %__MODULE__{} = overlays, keys: keys) do
    retained = MapSet.new(keys)

    groups =
      overlays.groups
      |> Enum.map(fn {group_key, members} ->
        {group_key, Enum.filter(members, &MapSet.member?(retained, &1))}
      end)
      |> Enum.reject(fn {_group_key, members} -> members == [] end)
      |> Map.new()

    %{overlays | groups: groups}
  end

  def member_color(index) when is_integer(index) and index >= 0 do
    Enum.at(@member_colors, rem(index, length(@member_colors)))
  end

  def kind_style(type), do: Map.get(@kind_styles, type, @kind_styles.room)

  def kind_label(type: type, count: 1), do: kind_style(type).singular
  def kind_label(type: type, count: _count), do: kind_style(type).label
end
