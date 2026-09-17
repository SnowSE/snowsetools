defmodule SnowSeToolsWeb.Scheduling.ScheduleCanvasEntries do
  @moduledoc """
  How the canvas is written down and read back: the translation between the
  cards on screen and the portable entries a saved layout stores.

  Pure data. `ScheduleDetailsOrder` owns the canvas; this owns its notation,
  including what to do about an entry naming an owner the current term does not
  have.
  """

  require Logger

  @default_card_size %{width: nil, scale: 1.0}
  @min_card_width 480
  @min_scale 0.5
  @max_scale 3.0

  def default_card_size, do: @default_card_size

  @doc "A card size from a resize gesture, held inside the sizes the UI allows."
  def card_size(width: width, scale: scale),
    do: %{width: normalize_width(width), scale: clamp_scale(scale)}

  def encode_card_size(%{width: width, scale: scale}),
    do: %{"width" => encode_card_width(width), "scale" => scale}

  defp encode_card_width(:full), do: "full"
  defp encode_card_width(width) when is_integer(width), do: width
  defp encode_card_width(_width), do: nil

  def decode_card_size(%{"width" => width, "scale" => scale}),
    do: %{width: normalize_width(width), scale: clamp_scale(scale)}

  def decode_card_size(_size), do: @default_card_size

  def resolve_layout_entries(entries, available_owner_keys) do
    Enum.reduce(entries, {[], []}, fn entry, {resolved, missing} ->
      case resolve_layout_entry(entry, available_owner_keys) do
        {:ok, resolved_entry, dropped} -> {resolved ++ [resolved_entry], missing ++ dropped}
        {:dropped, dropped} -> {resolved, missing ++ dropped}
      end
    end)
  end

  defp resolve_layout_entry(%{"kind" => "owner", "key" => key} = entry, available_owner_keys)
       when is_binary(key) do
    if owner_available?(key, available_owner_keys) do
      {:ok, {:owner, key, decode_card_size(entry["size"])}, []}
    else
      {:dropped, [key]}
    end
  end

  defp resolve_layout_entry(%{"kind" => "overlay", "members" => members} = entry, available)
       when is_list(members) do
    {kept, dropped} = Enum.split_with(members, &owner_available?(&1, available))

    case kept do
      [] -> {:dropped, dropped}
      [only_survivor] -> {:ok, {:owner, only_survivor, decode_card_size(entry["size"])}, dropped}
      _members -> {:ok, {:overlay, kept, decode_card_size(entry["size"])}, dropped}
    end
  end

  defp resolve_layout_entry(entry, _available_owner_keys) do
    Logger.warning("Ignored unrecognised saved layout entry #{inspect(entry)}")
    {:dropped, []}
  end

  # The term's owner metadata has not arrived yet, so nothing can be checked
  # against it. Keys of a known kind are accepted and the usual term-replacement
  # path prunes any that turn out not to exist.
  defp owner_available?(key, nil), do: owner_key_type(key) != nil

  defp owner_available?(key, available_owner_keys),
    do: MapSet.member?(available_owner_keys, key)

  defp normalize_width("full"), do: :full
  defp normalize_width(width) when is_integer(width), do: max(width, @min_card_width)
  defp normalize_width(width) when is_float(width), do: normalize_width(round(width))

  defp normalize_width(width) when is_binary(width) do
    case Integer.parse(width) do
      {value, _rest} -> normalize_width(value)
      :error -> nil
    end
  end

  defp normalize_width(_width), do: nil

  defp clamp_scale(scale) when is_number(scale),
    do: scale |> max(@min_scale) |> min(@max_scale) |> Kernel.*(1.0)

  defp clamp_scale(_scale), do: 1.0

  def owner_key_type("professor:" <> _name), do: :professor
  def owner_key_type("room:" <> _name), do: :room
  def owner_key_type("academic_program_semester:" <> _name), do: :academic_program_semester
  def owner_key_type(_key), do: nil
end
