defmodule SnowSeTools.Data.Uuid do
  @moduledoc """
  Converts between hyphenated UUID strings and the 16-byte binary format used by
  Postgrex.
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

  @doc """
  Convert a 16-byte binary UUID to its hyphenated string form.

      iex> Uuid.to_string(Uuid.to_binary("550e8400-e29b-41d4-a716-446655440000"))
      "550e8400-e29b-41d4-a716-446655440000"
  """
  def to_string(<<a::4-bytes, b::2-bytes, c::2-bytes, d::2-bytes, e::6-bytes>>) do
    [a, b, c, d, e]
    |> Enum.map(&Base.encode16(&1, case: :lower))
    |> Enum.join("-")
  end
end
