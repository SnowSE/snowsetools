defmodule SnowSeTools.Data.Access do
  @moduledoc """
  Pure authorization helpers. A user is a map with a `group_names` list
  (see `SnowSeTools.Data.User`).

  Every area of the app is gated by one or more groups, each granting a level:
  `:view` reads the area, `:edit` also changes it. An area with a single
  `:edit` role has no read-only tier — you either change it or you cannot open
  it. Members of `admin` (the super user group) can do everything and manage
  users and groups. A user with no groups at all is *pending approval* and can
  only see the approval page.
  """

  @admin_group "admin"

  @roles [
    %{
      area: :syllabi,
      level: :edit,
      group: "syllabus_admin",
      label: "Syllabi",
      description:
        "Syllabus search, school overviews, required elements, AI reports and syllabus sync."
    },
    %{
      area: :scheduling,
      level: :view,
      group: "scheduling_view",
      label: "Scheduling (view only)",
      description:
        "Read schedules for professors, rooms and program semesters, with conflicts and saved layouts. Cannot change a course or open change groups."
    },
    %{
      area: :scheduling,
      level: :edit,
      group: "scheduling_admin",
      label: "Scheduling",
      description: "Academic programs, schedule viewing, conflicts and schedule change groups."
    },
    %{
      area: :curriculum,
      level: :edit,
      group: "curriculum_admin",
      label: "Curriculum map",
      description:
        "Edit skills and course links, run the master-syllabus and AI review, accept suggestions and import the ABET matrix."
    },
    %{
      area: :discord,
      level: :edit,
      group: "discord_admin",
      label: "Discord",
      description:
        "Discord channels, roles, members, invites and student mapping (includes rosters)."
    },
    %{
      area: :admin,
      level: :edit,
      group: @admin_group,
      label: "Super user",
      description: "Full access to every area plus user and group management."
    }
  ]

  # Areas every approved user can read without a group of their own. Approved
  # users are faculty and staff, and the curriculum map is meant to be read by
  # all of them; only changing it takes a group.
  @open_areas [
    %{
      area: :curriculum,
      level: :view,
      group: nil,
      label: "Curriculum map",
      description:
        "Where each skill and learning outcome is introduced, reinforced and mastered across the program, with ABET coverage."
    }
  ]

  def admin_group, do: @admin_group

  @doc "Every role with its area, level, group name, label and description, in display order."
  def roles, do: @roles

  @doc "Group names that are seeded on boot and cannot be renamed or deleted."
  def protected_group_names, do: Enum.map(@roles, & &1.group)

  def protected_group?(name) when is_binary(name), do: name in protected_group_names()

  @doc "Every group that grants any access to `area`."
  def groups_for(area) do
    case Enum.filter(@roles, &(&1.area == area)) do
      [] -> raise ArgumentError, "unknown access area #{inspect(area)}"
      roles -> Enum.map(roles, & &1.group)
    end
  end

  @doc "The group that grants the right to change `area`."
  def edit_group_for(area) do
    case Enum.find(@roles, &(&1.area == area and &1.level == :edit)) do
      %{group: group} -> group
      nil -> raise ArgumentError, "no edit role for access area #{inspect(area)}"
    end
  end

  def area_for_group(group_name) do
    Enum.find(@roles, &(&1.group == group_name))
  end

  def admin?(user), do: @admin_group in group_names(user)

  @doc "A user with at least one group has been approved by a super user."
  def approved?(user), do: group_names(user) != []

  @doc "Can `user` open `area` at all? Super users can open every area."
  def can?(user, area) do
    names = group_names(user)

    @admin_group in names or Enum.any?(groups_for(area), &(&1 in names)) or
      (open_area?(area) and approved?(user))
  end

  defp open_area?(area), do: Enum.any?(@open_areas, &(&1.area == area))

  @doc """
  Can `user` change `area`, rather than only read it? Super users can change
  every area.
  """
  def can_edit?(user, area) do
    names = group_names(user)
    @admin_group in names or edit_group_for(area) in names
  end

  @doc """
  Areas the user may open, in display order (excluding :admin). An area the
  user holds at more than one level appears once, at the highest level.
  """
  def accessible_areas(user) do
    open = if approved?(user), do: @open_areas, else: []

    (@roles ++ open)
    |> Enum.reject(&(&1.area == :admin))
    |> Enum.filter(&(&1.group == nil or &1.group in group_names(user) or admin?(user)))
    |> Enum.group_by(& &1.area)
    |> Enum.map(fn {_area, roles} -> highest_role(roles) end)
    |> Enum.sort_by(&role_position/1)
  end

  defp highest_role(roles), do: Enum.find(roles, List.first(roles), &(&1.level == :edit))

  defp role_position(role), do: Enum.find_index(@roles, &(&1.area == role.area))

  defp group_names(%{group_names: names}) when is_list(names), do: names
  defp group_names(%{"group_names" => names}) when is_list(names), do: names
  defp group_names(_), do: []
end
