defmodule SnowSeTools.Scheduling.Instructor do
  @moduledoc """
  Who an instructor on a course is, for grouping their classes into one schedule.

  my.snow.edu sends each instructor as `%{"name", "email", "primary_instructor"}`.
  Names are not unique -- two different people named Michael Olson teach here --
  so a schedule is keyed by the lowercased email (`professor:<email>`), and only
  falls back to the name for the rare record without one. The name stays what
  people see; `labels/1` adds the email only where two people share a name.

  Keys used to be `professor:<name>`. `legacy_key/1` gives that old form so a
  saved layout or a browser's remembered canvas can be translated on load.
  """

  alias SnowSeTools.Data.Text

  @key_prefix "professor:"

  @doc "The instructor's name as sent, trimmed; nil when there is none."
  def name(%{"name" => name}) when is_binary(name), do: present(name)
  def name(%{name: name}) when is_binary(name), do: present(name)
  def name(name) when is_binary(name), do: present(name)
  def name(_instructor), do: nil

  @doc "The instructor's email, lowercased; nil when there is none."
  def email(%{"email" => email}) when is_binary(email), do: normalize_email(email)
  def email(%{email: email}) when is_binary(email), do: normalize_email(email)
  def email(_instructor), do: nil

  @doc """
  What tells this instructor apart from every other: their email, or their
  name when the record has no email. Nil when it has neither.
  """
  def identity(instructor), do: email(instructor) || name(instructor)

  @doc "The schedule owner key for this instructor, or nil."
  def owner_key(instructor) do
    case identity(instructor) do
      nil -> nil
      identity -> @key_prefix <> identity
    end
  end

  @doc "The identity inside a `professor:` owner key."
  def identity_from_key(@key_prefix <> identity) when identity != "", do: identity
  def identity_from_key(_key), do: nil

  @doc "The pre-email key for an instructor: `professor:<name>`."
  def legacy_key(instructor) do
    case name(instructor) do
      nil -> nil
      name -> @key_prefix <> name
    end
  end

  @doc """
  Every distinct instructor in `instructors` (any mix of maps from different
  courses), as `%{identity => %{name, email, label}}`. The label is the name,
  with the email added when another instructor here has the same name.
  """
  def labels(instructors) do
    people =
      instructors
      |> Enum.flat_map(fn instructor ->
        case identity(instructor) do
          nil ->
            []

          identity ->
            [{identity, %{name: name(instructor) || identity, email: email(instructor)}}]
        end
      end)
      |> Enum.uniq_by(&elem(&1, 0))

    shared_names =
      people
      |> Enum.frequencies_by(fn {_identity, person} -> String.downcase(person.name) end)
      |> Enum.filter(fn {_name, count} -> count > 1 end)
      |> MapSet.new(&elem(&1, 0))

    Map.new(people, fn {identity, person} ->
      label =
        if MapSet.member?(shared_names, String.downcase(person.name)) and person.email do
          "#{person.name} (#{person.email})"
        else
          person.name
        end

      {identity, Map.put(person, :label, label)}
    end)
  end

  @doc """
  Finds the one instructor `text` refers to among `people` (the map from
  `labels/1`): an owner key, an email, a label, or a name nobody else here
  has. Nil when it matches no one, or matches more than one person.
  """
  def resolve(text, people) when is_binary(text) and is_map(people) do
    wanted = text |> String.trim() |> String.downcase()
    wanted_identity = identity_from_key(String.trim(text))

    matches =
      Enum.filter(people, fn {identity, person} ->
        identity == wanted_identity or String.downcase(identity) == wanted or
          String.downcase(person.label) == wanted
      end)

    matches =
      if matches == [],
        do:
          Enum.filter(people, fn {_identity, person} -> String.downcase(person.name) == wanted end),
        else: matches

    case matches do
      [{identity, person}] -> Map.put(person, :identity, identity)
      _none_or_ambiguous -> nil
    end
  end

  def resolve(_text, _people), do: nil

  defp normalize_email(email) do
    case email |> String.trim() |> String.downcase() do
      "" -> nil
      email -> email
    end
  end

  defp present(text) do
    if Text.blank?(text), do: nil, else: String.trim(text)
  end
end
