defmodule SnowSeTools.Data.EmailList do
  # Admins add people by pasting a list straight out of Outlook, which looks
  # like: "First Last" <first.last@snow.edu>; "Other Person" <other@snow.edu>.
  # Pulling the addresses out by pattern rather than splitting on a separator
  # means display names, quotes, and whichever of ; , or a newline separates the
  # entries all stop mattering — including names that contain a comma.
  @email_pattern ~r/[^\s<>()\[\],;:"']+@[^\s<>()\[\],;:"']+\.[A-Za-z]{2,}/

  # Addresses are lowercased because the list a directory hands out is
  # inconsistently cased ("First.Last@snow.edu"), while the address the
  # identity provider sends at login is not, and `users.email` is matched
  # exactly.
  def parse(value) when is_binary(value) do
    @email_pattern
    |> Regex.scan(value)
    |> Enum.map(fn [email] -> String.downcase(email) end)
    |> Enum.uniq()
  end

  def parse(_value), do: []
end
