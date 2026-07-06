defmodule SnowSeTools.Discord.DiscordApi do
  @base_url "https://discord.com/api/v10/"

  def fetch_guild do
    with {:ok, guild_id} <- discord_guild_id(),
         {:ok, headers} <- auth_headers() do
      request(:get, "guilds/#{guild_id}", headers: headers)
    end
  end

  def fetch_current_user do
    with {:ok, headers} <- auth_headers() do
      request(:get, "users/@me", headers: headers)
    end
  end

  def fetch_channels do
    with {:ok, guild_id} <- discord_guild_id(),
         {:ok, headers} <- auth_headers() do
      request(:get, "guilds/#{guild_id}/channels", headers: headers)
    end
  end

  def fetch_roles do
    with {:ok, guild_id} <- discord_guild_id(),
         {:ok, headers} <- auth_headers() do
      request(:get, "guilds/#{guild_id}/roles", headers: headers)
    end
  end

  def fetch_invites do
    with {:ok, guild_id} <- discord_guild_id(),
         {:ok, headers} <- auth_headers() do
      request(:get, "guilds/#{guild_id}/invites", headers: headers)
    end
  end

  def add_role_to_member(member_id: member_id, role_id: role_id) do
    with {:ok, guild_id} <- discord_guild_id(),
         {:ok, headers} <- auth_headers() do
      request(:put, "guilds/#{guild_id}/members/#{member_id}/roles/#{role_id}", headers: headers)
    end
  end

  def create_text_channel(name: name, parent_id: parent_id) do
    with {:ok, guild_id} <- discord_guild_id(),
         {:ok, headers} <- auth_headers() do
      request(:post, "guilds/#{guild_id}/channels",
        headers: headers,
        json: %{
          "name" => name,
          "type" => 0,
          "parent_id" => parent_id
        }
      )
    end
  end

  def rename_channel(channel_id: channel_id, new_name: new_name) do
    with {:ok, headers} <- auth_headers() do
      request(:patch, "channels/#{channel_id}", headers: headers, json: %{"name" => new_name})
    end
  end

  def delete_channel(channel_id: channel_id) do
    with {:ok, headers} <- auth_headers() do
      request(:delete, "channels/#{channel_id}", headers: headers)
    end
  end

  def fetch_members do
    with {:ok, guild_id} <- discord_guild_id(),
         {:ok, headers} <- auth_headers() do
      fetch_member_page(
        guild_id: guild_id,
        headers: headers,
        after_user_id: "0",
        members: []
      )
    end
  end

  defp fetch_member_page(
         guild_id: guild_id,
         headers: headers,
         after_user_id: after_user_id,
         members: members
       ) do
    path = "guilds/#{guild_id}/members?limit=1000&after=#{after_user_id}"

    case request(:get, path, headers: headers) do
      {:ok, []} ->
        {:ok, members}

      {:ok, page_members} when is_list(page_members) ->
        case List.last(page_members) do
          %{"user" => %{"id" => last_user_id}} when is_binary(last_user_id) ->
            fetch_member_page(
              guild_id: guild_id,
              headers: headers,
              after_user_id: last_user_id,
              members: members ++ page_members
            )

          _ ->
            {:ok, members ++ page_members}
        end

      {:ok, body} ->
        {:error, "Discord returned unexpected members payload: #{inspect(body)}"}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp request(method, path, headers: headers),
    do: request(method, path, headers: headers, json: nil)

  defp request(method, path, headers: headers, json: json) do
    request_opts = [method: method, url: @base_url <> path, headers: headers]
    request_opts = if is_nil(json), do: request_opts, else: Keyword.put(request_opts, :json, json)

    case Req.request(request_opts) do
      {:ok, %Req.Response{status: status, body: body}} when status in 200..299 ->
        {:ok, body}

      {:ok, %Req.Response{status: status, body: body}} ->
        {:error, "Discord request to #{path} returned status #{status}: #{inspect(body)}"}

      {:error, reason} ->
        {:error, "Discord request to #{path} failed: #{format_error(reason)}"}
    end
  end

  defp auth_headers do
    case discord_bot_token() do
      {:ok, token} ->
        {:ok,
         [
           {"authorization", "Bot #{token}"},
           {"user-agent", "SimpleSyllabusReporter/1.0"}
         ]}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp discord_bot_token do
    case Application.get_env(:snow_se_tools, :discord, [])[:bot_token] ||
           System.get_env("DISCORD_BOT_TOKEN") do
      token when is_binary(token) and token != "" ->
        {:ok, token}

      _ ->
        {:error, "Discord bot token is not configured in DISCORD_BOT_TOKEN."}
    end
  end

  defp discord_guild_id do
    case Application.get_env(:snow_se_tools, :discord, [])[:guild_id] ||
           System.get_env("DISCORD_GUILD_ID") do
      guild_id when is_binary(guild_id) and guild_id != "" ->
        {:ok, guild_id}

      _ ->
        {:error, "Discord guild id is not configured in DISCORD_GUILD_ID."}
    end
  end

  defp format_error(%{message: message}) when is_binary(message), do: message
  defp format_error(reason), do: inspect(reason)
end
