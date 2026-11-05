defmodule SnowSeToolsWeb.ReloadOnNewBuild do
  @moduledoc """
  Reloads a tab that reconnects to a newer deploy than the one it loaded.

  A deploy restarts the server, and every open tab reconnects on its own. But
  it reconnects running the JavaScript and CSS it loaded before the deploy,
  against a server that now renders markup for the new ones -- which is how
  tabs ended up stuck on "Something went wrong" until someone refreshed.

  The CSS and JS tags are marked `phx-track-static`, so LiveView can tell
  (`static_changed?/1`) when the client's files are not this build's. It does
  not act on that by itself; this does, with a full reload of the page the tab
  was on. The canvas, term and layout are restored from the browser on load,
  so the reload costs at most an unsaved dialog.

  Only the root LiveView of a connected mount can answer, so nested LiveViews
  and the disconnected render pass straight through.
  """

  import Phoenix.LiveView

  def on_mount(:default, _params, _session, %{parent_pid: nil} = socket) do
    if connected?(socket) and static_changed?(socket) do
      {:halt, redirect(socket, to: current_path(socket))}
    else
      {:cont, socket}
    end
  end

  def on_mount(:default, _params, _session, socket), do: {:cont, socket}

  # app.js sends the page's own path and query string as `return_to` on every
  # connect. A "//host" path would leave the site, so it is refused.
  defp current_path(socket) do
    case get_connect_params(socket) do
      %{"return_to" => "//" <> _} -> "/"
      %{"return_to" => "/" <> _ = path} -> path
      _ -> "/"
    end
  end
end
