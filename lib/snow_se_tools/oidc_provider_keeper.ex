defmodule SnowSeTools.OidcProviderKeeper do
  @moduledoc """
  Keeps the oidcc provider worker running without letting the identity provider
  take the whole app down with it.

  The worker loads discovery the moment it starts and exits if the issuer is
  unreachable. Left under the top-level supervisor, it restarts in a tight loop,
  burns through the restart budget in milliseconds, and the application dies —
  so an IdP outage became a site outage. Here it is linked to this process
  instead and restarted with backoff: while the IdP is down only login fails,
  and it picks back up on its own once the IdP returns.
  """

  use GenServer

  require Logger

  @initial_backoff :timer.seconds(2)
  @max_backoff :timer.minutes(1)

  def start_link(worker_opts) do
    GenServer.start_link(__MODULE__, worker_opts)
  end

  @impl true
  def init(worker_opts) do
    Process.flag(:trap_exit, true)

    {:ok, %{opts: worker_opts, worker: nil, backoff: @initial_backoff},
     {:continue, :start_worker}}
  end

  @impl true
  def handle_continue(:start_worker, state), do: {:noreply, start_worker(state)}

  @impl true
  def handle_info(:start_worker, state), do: {:noreply, start_worker(state)}

  def handle_info({:EXIT, pid, reason}, %{worker: pid} = state) do
    Logger.warning(
      "OIDC provider worker exited, retrying in #{div(state.backoff, 1000)}s: #{inspect(reason)}"
    )

    Process.send_after(self(), :start_worker, state.backoff)
    {:noreply, %{state | worker: nil, backoff: min(state.backoff * 2, @max_backoff)}}
  end

  def handle_info({:EXIT, _pid, _reason}, state), do: {:noreply, state}

  # A worker that stays up past one full backoff window has loaded discovery,
  # so the next failure starts the backoff over rather than at the ceiling.
  def handle_info({:healthy, pid}, %{worker: pid} = state),
    do: {:noreply, %{state | backoff: @initial_backoff}}

  def handle_info({:healthy, _pid}, state), do: {:noreply, state}

  @impl true
  def terminate(_reason, %{worker: pid}) when is_pid(pid) do
    Process.exit(pid, :shutdown)
  end

  def terminate(_reason, _state), do: :ok

  defp start_worker(state) do
    case Oidcc.ProviderConfiguration.Worker.start_link(state.opts) do
      {:ok, pid} ->
        Process.send_after(self(), {:healthy, pid}, @max_backoff)
        %{state | worker: pid}

      {:error, reason} ->
        send(self(), {:EXIT, :start_failed, reason})
        %{state | worker: :start_failed}
    end
  end
end
