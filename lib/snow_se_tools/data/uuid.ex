defmodule SnowSeTools.Data.Uuid do
  @moduledoc """
  Converts UUID strings to the 16-byte binary format expected by Postgrex.
  """

  @doc """
  Convert a hyphenated UUID string to a 16-byte binary for use as a query parameter.

      iex> Uuid.to_binary("550e8400-e29b-41d4-a716-446655440000")
      "U\xB4\x00\xE2\x9BArT\xA7\x16DGTS\x00\x00"
  """
  def to_binary(uuid_string) when is_binary(uuid_string) do
    uuid_string
    |> String.replace("-", "")
    |> Base.decode16!(case: :lower)
  end
end
