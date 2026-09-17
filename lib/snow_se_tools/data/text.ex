defmodule SnowSeTools.Data.Text do
  @moduledoc """
  Small string predicates shared across areas.

  `blank?/1` had grown a dozen private copies that did not agree on what a
  non-string is: some called a number blank, others called it present. Here a
  value is blank when it is `nil` or a string with nothing but whitespace in it.
  Anything else — a number, a map, a list — is something, so it is not blank.
  """

  @doc """
  A value is blank when it is `nil` or a string of nothing but whitespace.
  Anything else — a number, a map, a list — is something.
  """
  def blank?(nil), do: true
  def blank?(value) when is_binary(value), do: String.trim(value) == ""
  def blank?(_value), do: false

  def present?(value), do: not blank?(value)

  @doc """
  Stricter: blank unless the value *is* a non-empty string. Callers that build
  display text or database keys out of a value want this one — a room number
  that arrived as an integer is not a room name, and rendering it as one would
  invent an owner that no other part of the system knows about.
  """
  def blank_string?(value) when is_binary(value), do: String.trim(value) == ""
  def blank_string?(_value), do: true

  def present_string?(value), do: not blank_string?(value)
end
