defmodule SnowSeTools.Data.DbHelpersTest do
  use ExUnit.Case, async: true

  alias SnowSeTools.Data.{DbHelpers, Uuid}

  test "uuid columns come back as hyphenated strings" do
    {:ok, [row]} = DbHelpers.query("SELECT gen_random_uuid() AS id", %{})
    assert row["id"] =~ ~r/^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/
  end

  test "16-character text values are not mistaken for uuids" do
    {:ok, [row]} =
      DbHelpers.query("SELECT $(name)::text AS name", %{"name" => "Digital Circuits"})

    assert row["name"] == "Digital Circuits"
  end

  test "uuid params accept both string and binary forms" do
    id = "550e8400-e29b-41d4-a716-446655440000"

    {:ok, [row]} = DbHelpers.query("SELECT $(id)::uuid AS id", %{"id" => id})
    assert row["id"] == id

    {:ok, [row]} = DbHelpers.query("SELECT $(id)::uuid AS id", %{"id" => Uuid.to_binary(id)})
    assert row["id"] == id
  end

  describe "error reasons" do
    test "a missing named parameter is reported, not raised at the caller" do
      assert DbHelpers.query("SELECT $(missing)::text", %{}) == {:error, :missing_param}
    end

    test "a unique violation is its own reason" do
      {:ok, _} =
        DbHelpers.query(
          "CREATE TABLE IF NOT EXISTS db_helpers_unique_test (id TEXT PRIMARY KEY)",
          %{}
        )

      {:ok, _} =
        DbHelpers.query("INSERT INTO db_helpers_unique_test (id) VALUES ($(id))", %{"id" => "a"})

      assert DbHelpers.query("INSERT INTO db_helpers_unique_test (id) VALUES ($(id))", %{
               "id" => "a"
             }) == {:error, :not_unique}

      {:ok, _} = DbHelpers.query("DROP TABLE db_helpers_unique_test", %{})
    end

    test "anything else keeps its message for the log" do
      assert {:error, {:query_failed, message}} =
               DbHelpers.query("SELECT * FROM nope_not_here", %{})

      assert is_binary(message)
    end
  end

  describe "query_or/3,4" do
    test "hands back the default instead of an error tuple" do
      assert DbHelpers.query_or("SELECT 1 AS n", %{}, []) == [%{"n" => 1}]
      assert DbHelpers.query_or("SELECT * FROM nope_not_here", %{}, []) == []
    end
  end
end
