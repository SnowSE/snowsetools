defmodule SnowSeTools.Data.DbHelpersTest do
  use ExUnit.Case, async: true

  alias SnowSeTools.Data.{DbHelpers, Uuid}

  test "uuid columns come back as hyphenated strings" do
    [row] = DbHelpers.run_sql("SELECT gen_random_uuid() AS id", %{})
    assert row["id"] =~ ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
  end

  test "16-character text values are not mistaken for uuids" do
    [row] = DbHelpers.run_sql("SELECT $(name)::text AS name", %{"name" => "Digital Circuits"})
    assert row["name"] == "Digital Circuits"
  end

  test "uuid params accept both string and binary forms" do
    id = "550e8400-e29b-41d4-a716-446655440000"

    [row] = DbHelpers.run_sql("SELECT $(id)::uuid AS id", %{"id" => id})
    assert row["id"] == id

    [row] = DbHelpers.run_sql("SELECT $(id)::uuid AS id", %{"id" => Uuid.to_binary(id)})
    assert row["id"] == id
  end
end
