defmodule SnowSeToolsWeb.Scheduling.CourseChangeIntent do
  require Logger

  alias SnowSeTools.Scheduling.ScheduleUtils

  @mwf_days ["Monday", "Wednesday", "Friday"]
  @tth_days ["Tuesday", "Thursday"]

  def move_course_attrs(params) when is_map(params) do
    with {:ok, owner} <- owner_from_params(params),
         {:ok, meeting} <- meeting_from_params(params),
         {:ok, start_time} <- fetch_string(params, "target_time"),
         {:ok, target_day} <- fetch_string(params, "target_day"),
         {:ok, crn} <- fetch_string(params, "crn"),
         {:ok, term} <- fetch_string(params, "term") do
      original_meet_info = Map.get(params, "meet_info", [])
      original_days = Map.get(meeting, "days", [])
      new_days = new_days(original_days, target_day)
      end_time = end_time(start_time, meeting, new_days, Map.get(params, "credit_hours"))
      target_room = target_room(owner, meeting)

      {:ok,
       %{
         "crn" => crn,
         "term" => term,
         "course_name" => Map.get(params, "course_name"),
         "target_professor" => target_professor(owner, params),
         "meet_info" =>
           replace_meeting(
             original_meet_info,
             meeting,
             new_meeting(meeting, new_days, start_time, end_time, target_room)
           ),
         "operation" => "update"
       }}
    end
  end

  def edit_course_attrs(params) when is_map(params) do
    with {:ok, owner} <- owner_from_params(params),
         {:ok, crn} <- fetch_string(params, "crn"),
         {:ok, term} <- fetch_string(params, "term"),
         {:ok, start_time} <- fetch_string(params, "start_time"),
         {:ok, end_time} <- fetch_string(params, "end_time") do
      days = Map.get(params, "days", []) |> Enum.filter(&is_binary/1)
      original_meet_info = Map.get(params, "meet_info", [])
      original_meeting = List.first(original_meet_info) || %{}
      target_room = target_room(owner, original_meeting)

      {:ok,
       %{
         "crn" => crn,
         "term" => term,
         "course_name" => Map.get(params, "course_name"),
         "target_professor" => target_professor(owner, params),
         "meet_info" => [
           new_meeting(original_meeting, days, start_time, end_time, target_room)
         ],
         "operation" => "update"
       }}
    end
  end

  def delete_course_attrs(params) when is_map(params) do
    with {:ok, crn} <- fetch_string(params, "crn"),
         {:ok, term} <- fetch_string(params, "term") do
      {:ok,
       %{
         "crn" => crn,
         "term" => term,
         "course_name" => "__DELETED__",
         "target_professor" => "",
         "meet_info" => [],
         "operation" => "update"
       }}
    end
  end

  defp owner_from_params(params) do
    with {:ok, type} <- fetch_string(params, "owner_type"),
         {:ok, name} <- fetch_string(params, "owner_name") do
      {:ok, %{type: type, name: name}}
    end
  end

  defp meeting_from_params(params) do
    case Map.get(params, "meeting") do
      %{} = meeting -> {:ok, meeting}
      _other -> {:error, :missing_meeting}
    end
  end

  defp fetch_string(params, key) do
    case Map.get(params, key) do
      value when is_binary(value) and value != "" -> {:ok, value}
      _other -> {:error, {:missing_string, key}}
    end
  end

  defp new_days([_single_day], target_day), do: [target_day]

  defp new_days(original_days, target_day) do
    original_mwf? = Enum.all?(original_days, &(&1 in @mwf_days))
    original_tth? = Enum.all?(original_days, &(&1 in @tth_days))

    cond do
      original_mwf? and target_day in @tth_days -> @tth_days
      original_tth? and target_day in @mwf_days -> @mwf_days
      true -> original_days
    end
  end

  defp end_time(start_time, original_meeting, new_days, credit_hours) do
    duration =
      if is_number(credit_hours) and
           length(new_days) != length(Map.get(original_meeting, "days", [])) do
        round(credit_hours * 50 / max(length(new_days), 1))
      else
        original_duration(original_meeting)
      end

    start_time
    |> parse_minutes()
    |> Kernel.+(duration)
    |> format_time()
  end

  defp original_duration(%{"start_time" => start_time, "end_time" => end_time})
       when is_binary(start_time) and is_binary(end_time) do
    max(parse_minutes(end_time) - parse_minutes(start_time), 30)
  end

  defp original_duration(_meeting), do: 50

  defp replace_meeting([], _original_meeting, new_meeting), do: [new_meeting]

  defp replace_meeting([_first | rest], _original_meeting, new_meeting) do
    [new_meeting | rest]
  end

  defp new_meeting(original_meeting, days, start_time, end_time, nil) do
    original_meeting
    |> Map.put("days", days)
    |> Map.put("start_time", start_time)
    |> Map.put("end_time", end_time)
  end

  defp new_meeting(original_meeting, days, start_time, end_time, room_name) do
    {building, room} = room_parts(room_name, original_meeting)

    original_meeting
    |> Map.put("days", days)
    |> Map.put("start_time", start_time)
    |> Map.put("end_time", end_time)
    |> Map.put("building", building)
    |> Map.put("room", room)
  end

  defp target_professor(%{type: "professor", name: name}, _params), do: name

  defp target_professor(_owner, params) do
    params
    |> Map.get("instructors", [])
    |> List.wrap()
    |> Enum.find("", &is_binary/1)
  end

  defp target_room(%{type: "room", name: name}, _meeting), do: name

  defp target_room(_owner, meeting) do
    ScheduleUtils.room_name(meeting: meeting)
  end

  defp room_parts(room_name, %{"building" => building, "room" => room})
       when is_binary(building) and is_binary(room) do
    if room_name == ScheduleUtils.room_name(meeting: %{"building" => building, "room" => room}) do
      {building, room}
    else
      split_room(room_name)
    end
  end

  defp room_parts(room_name, %{"building_code" => building_code, "room" => room})
       when is_binary(building_code) and is_binary(room) do
    if room_name ==
         ScheduleUtils.room_name(meeting: %{"building_code" => building_code, "room" => room}) do
      {nil, room}
    else
      split_room(room_name)
    end
  end

  defp room_parts(room_name, _original_meeting), do: split_room(room_name)

  defp split_room(room_name) do
    case Regex.run(~r/^(.+?)\s+([^\s]+)$/, room_name) do
      [_all, building, room] -> {building, room}
      _other -> {nil, room_name}
    end
  end

  defp parse_minutes(<<hour::binary-size(2), ":", minute::binary-size(2), _rest::binary>>) do
    {hour, ""} = Integer.parse(hour)
    {minute, ""} = Integer.parse(minute)
    hour * 60 + minute
  rescue
    _error -> 8 * 60
  end

  defp parse_minutes(_time), do: 8 * 60

  defp format_time(minutes) do
    hour = div(minutes, 60)
    minute = rem(minutes, 60)

    "#{String.pad_leading(to_string(hour), 2, "0")}:#{String.pad_leading(to_string(minute), 2, "0")}"
  end
end
