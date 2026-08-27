defmodule SnowSeTools.Data.Access do
  @moduledoc """
  Pure authorization helpers. A user is a map with a `group_names` list
  (see `SnowSeTools.Data.User`).

  Every area of the app is gated by one group. Members of `admin` (the super
  user group) can access everything and manage users and groups. A user with
  no groups at all is *pending approval* and can only see the approval page.
  """

  @admin_group "admin"

  @areas [
    %{
      area: :syllabi,
      group: "syllabus_admin",
      label: "Syllabi",
      description:
        "Syllabus search, school overviews, required elements, AI reports and syllabus sync."
    },
    %{
      area: :scheduling,
      group: "scheduling_admin",
      label: "Scheduling",
      description: "Academic programs, schedule viewing, conflicts and schedule change groups."
    },
    %{
      area: :discord,
      group: "discord_admin",
      label: "Discord",
      description:
        "Discord channels, roles, members, invites and student mapping (includes rosters)."
    },
    %{
      area: :admin,
      group: @admin_group,
      label: "Super user",
      description: "Full access to every area plus user and group management."
    }
  ]

  def admin_group, do: @admin_group

  @doc "Every access area with its group name, label and description, in display order."
  def areas, do: @areas

  @doc "Group names that are seeded on boot and cannot be renamed or deleted."
  def protected_group_names, do: Enum.map(@areas, & &1.group)

  def protected_group?(name) when is_binary(name), do: name in protected_group_names()

  @doc "The group that grants access to `area`."
  def group_for(area) do
    case Enum.find(@areas, &(&1.area == area)) do
      %{group: group} -> group
      nil -> raise ArgumentError, "unknown access area #{inspect(area)}"
    end
  end

  def area_for_group(group_name) do
    Enum.find(@areas, &(&1.group == group_name))
  end

  def admin?(user), do: @admin_group in group_names(user)

  @doc "A user with at least one group has been approved by a super user."
  def approved?(user), do: group_names(user) != []

  @doc "Can `user` use `area`? Super users can use every area."
  def can?(user, area) do
    names = group_names(user)
    @admin_group in names or group_for(area) in names
  end

  @doc "Areas the user may use, in display order (excluding :admin)."
  def accessible_areas(user) do
    @areas
    |> Enum.reject(&(&1.area == :admin))
    |> Enum.filter(&can?(user, &1.area))
  end

  defp group_names(%{group_names: names}) when is_list(names), do: names
  defp group_names(%{"group_names" => names}) when is_list(names), do: names
  defp group_names(_), do: []
end
