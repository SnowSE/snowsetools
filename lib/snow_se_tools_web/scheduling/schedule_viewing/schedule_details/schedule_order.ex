defmodule SnowSeToolsWeb.Scheduling.ScheduleOrder do
  require Logger

  defstruct keys: [], key_set: MapSet.new()

  def new(), do: %__MODULE__{}

  def new(keys: keys) when is_list(keys) do
    Enum.reduce(keys, new(), fn key, order ->
      put(order: order, key: key)
    end)
  end

  def to_list(%__MODULE__{keys: keys}), do: keys

  def size(%__MODULE__{keys: keys}), do: length(keys)

  def member?(order: %__MODULE__{key_set: key_set}, key: key) when is_binary(key) do
    MapSet.member?(key_set, key)
  end

  def put(order: %__MODULE__{} = order, key: key) when is_binary(key) do
    if member?(order: order, key: key) do
      order
    else
      %__MODULE__{
        order
        | keys: order.keys ++ [key],
          key_set: MapSet.put(order.key_set, key)
      }
    end
  end

  def delete(order: %__MODULE__{} = order, key: key) when is_binary(key) do
    if member?(order: order, key: key) do
      %__MODULE__{
        order
        | keys: Enum.reject(order.keys, &(&1 == key)),
          key_set: MapSet.delete(order.key_set, key)
      }
    else
      order
    end
  end

  def retain_keys(order: %__MODULE__{} = order, keys: keys) when is_list(keys) or is_map(keys) do
    retained_keys = MapSet.new(keys)

    %__MODULE__{
      order
      | keys: Enum.filter(order.keys, &MapSet.member?(retained_keys, &1)),
        key_set: MapSet.intersection(order.key_set, retained_keys)
    }
  end

  def move_before(order: %__MODULE__{} = order, dragged_key: dragged_key, target_key: nil)
      when is_binary(dragged_key) do
    if member?(order: order, key: dragged_key) do
      move_to_end(order: order, key: dragged_key)
    else
      Logger.warning("ScheduleOrder ignored move-to-end for missing key #{inspect(dragged_key)}")

      order
    end
  end

  def move_before(order: %__MODULE__{} = order, dragged_key: dragged_key, target_key: target_key)
      when is_binary(dragged_key) and is_binary(target_key) do
    cond do
      dragged_key == target_key ->
        order

      !member?(order: order, key: dragged_key) ->
        Logger.warning(
          "ScheduleOrder ignored reorder because dragged key #{inspect(dragged_key)} is missing"
        )

        order

      !member?(order: order, key: target_key) ->
        Logger.warning(
          "ScheduleOrder ignored reorder because target key #{inspect(target_key)} is missing"
        )

        order

      true ->
        reordered_keys =
          reorder_keys(
            keys: order.keys,
            dragged_key: dragged_key,
            target_key: target_key
          )

        %__MODULE__{
          order
          | keys: reordered_keys,
            key_set: MapSet.new(reordered_keys)
        }
    end
  end

  defp move_to_end(order: %__MODULE__{} = order, key: key) do
    reordered_keys =
      order.keys
      |> Enum.reject(&(&1 == key))
      |> Kernel.++([key])

    %__MODULE__{
      order
      | keys: reordered_keys,
        key_set: MapSet.new(reordered_keys)
    }
  end

  defp reorder_keys(keys: keys, dragged_key: dragged_key, target_key: target_key) do
    remaining_keys = Enum.reject(keys, &(&1 == dragged_key))

    {before_target, after_target} = Enum.split_while(remaining_keys, &(&1 != target_key))

    before_target ++ [dragged_key | after_target]
  end
end
