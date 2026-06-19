defmodule SnowSeTools.TestDatabase do
  @schema_path Path.expand("../../schema.sql", __DIR__)

  def reset! do
    Ecto.Adapters.SQL.query!(SnowSeTools.Repo, "DROP SCHEMA IF EXISTS public CASCADE", [])
    Ecto.Adapters.SQL.query!(SnowSeTools.Repo, "CREATE SCHEMA public", [])
    Ecto.Adapters.SQL.query!(SnowSeTools.Repo, "CREATE EXTENSION IF NOT EXISTS pgcrypto", [])

    @schema_path
    |> File.read!()
    |> sql_statements()
    |> Enum.each(&Ecto.Adapters.SQL.query!(SnowSeTools.Repo, &1, []))
  end

  defp sql_statements(sql) do
    sql
    |> String.split("\n")
    |> Enum.reject(&(String.trim(&1) == "" or String.starts_with?(String.trim(&1), "--")))
    |> Enum.join("\n")
    |> String.split(";")
    |> Enum.map(&String.trim/1)
    |> Enum.reject(&(&1 == ""))
  end
end
