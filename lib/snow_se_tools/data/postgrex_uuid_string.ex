defmodule SnowSeTools.Data.PostgrexUuidString do
  @moduledoc """
  Postgrex extension that decodes Postgres `uuid` columns straight to hyphenated
  strings, and accepts either a hyphenated string or a 16-byte binary as a query
  parameter.

  This replaces guessing "is this 16-byte value a UUID?" from the raw row, which
  wrongly hex-encoded any 16-character TEXT value (e.g. "Digital Circuits").
  """
  import Postgrex.BinaryUtils, warn: false
  @behaviour Postgrex.Extension

  def init(opts), do: opts

  def matching(_), do: [send: "uuid_send"]

  def format(_), do: :binary

  def encode(_) do
    quote location: :keep do
      <<_::128>> = raw ->
        [<<16::int32()>> | raw]

      uuid when is_binary(uuid) and byte_size(uuid) == 36 ->
        [<<16::int32()>> | SnowSeTools.Data.Uuid.to_binary(uuid)]
    end
  end

  def decode(_) do
    quote location: :keep do
      <<16::int32(), raw::binary-size(16)>> -> SnowSeTools.Data.Uuid.to_string(raw)
    end
  end
end

Postgrex.Types.define(
  SnowSeTools.Data.PostgresTypes,
  [SnowSeTools.Data.PostgrexUuidString] ++ Ecto.Adapters.Postgres.extensions(),
  []
)
