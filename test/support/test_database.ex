defmodule SnowSeTools.TestDatabase do
  @moduledoc """
  Builds the one database the whole suite shares. See `SnowSeToolsWeb.ConnCase`
  for what that means for the tests themselves.
  """

  @schema_path Path.expand("../../schema.sql", __DIR__)

  # AccessControl.create_user/1 seeds the built-in groups and grants admin to
  # the first row in users. Left to chance that lands on whichever test happens
  # to run first, which then quietly holds super-user rights. Spending it on a
  # throwaway account makes every test account start with exactly the groups it
  # asked for.
  @bootstrap_email "suite-bootstrap@example.com"

  def seed_access_control! do
    {:ok, _user} = SnowSeTools.Data.AccessControl.create_user(email: @bootstrap_email)
    :ok
  end

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
