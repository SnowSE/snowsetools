defmodule SimpleSyllabusReporter.Cache do
  @moduledoc """
  Simple ETS-backed cache with per-entry TTL.

  Entries are stored as `{key, value, expires_at}` where `expires_at` is a
  monotonic millisecond timestamp. Stale entries are swept every minute.
  """
  use GenServer

  @table __MODULE__
  @sweep_interval :timer.minutes(1)
  @default_ttl :timer.hours(6)

  # --- Public API ---

  def start_link(_opts) do
    GenServer.start_link(__MODULE__, [], name: __MODULE__)
  end

  @doc "Fetch a cached value. Returns `{:ok, value}` or `:miss`."
  def get(key) do
    case :ets.lookup(@table, key) do
      [{^key, value, expires_at}] ->
        if System.monotonic_time(:millisecond) < expires_at do
          {:ok, value}
        else
          :ets.delete(@table, key)
          :miss
        end

      [] ->
        :miss
    end
  end

  @doc "Store a value. TTL defaults to 6 hours."
  def put(key, value, ttl \\ @default_ttl) do
    expires_at = System.monotonic_time(:millisecond) + ttl
    :ets.insert(@table, {key, value, expires_at})
    :ok
  end

  @doc "Remove a single cached entry."
  def invalidate(key), do: :ets.delete(@table, key)

  @doc "Clear all cached entries."
  def clear, do: :ets.delete_all_objects(@table)

  @doc """
  Wraps a `def` so that its `{:ok, value}` result is automatically cached.

  The cache key is `{CurrentModule, :function_name, [arg1, arg2, ...]}`.
  Only successful `{:ok, value}` returns are cached; errors pass through
  unchanged.

  ## Usage

      import SimpleSyllabusReporter.Cache, only: [ttl_cache: 1]

      ttl_cache def expensive_call(id) do
        # returns {:ok, result} or {:error, reason}
      end

  For functions whose arguments need normalisation before caching, keep a
  thin public wrapper that normalises then calls the `ttl_cache`-annotated
  function:

      def search(raw_filters) do
        fetch(normalise(raw_filters))
      end

      ttl_cache def fetch(normalised_filters) do
        # HTTP call
      end
  """
  defmacro ttl_cache({:def, _def_meta, [{name, name_meta, raw_args}]}, do: body) do
    raw_args = raw_args || []
    impl_name = :"__ttl_#{name}_impl"

    # For each arg build three things:
    #   outer_arg  – pattern used in the public def (kept as-is, incl. defaults)
    #   key_var    – variable reference used to build the cache key
    #   impl_arg   – pattern used in the private impl def (defaults stripped)
    processed =
      raw_args
      |> Enum.with_index()
      |> Enum.map(fn
        # Plain variable  e.g.  foo
        {{var_name, _meta, ctx} = var, _i}
        when is_atom(var_name) and (is_nil(ctx) or is_atom(ctx)) ->
          {var, var, var}

        # Default argument  e.g.  foo \\ default
        {{:\\, _, [{var_name, _meta, ctx} = var, _default]} = with_default, _i}
        when is_atom(var_name) and (is_nil(ctx) or is_atom(ctx)) ->
          # outer keeps the default; impl and key use the plain var
          {with_default, var, var}

        # Complex pattern  e.g.  %{id: id}
        {pattern, i} ->
          capture = Macro.var(:"_ttl_arg#{i}", __CALLER__.module)
          {{:=, [], [capture, pattern]}, capture, pattern}
      end)

    outer_args = Enum.map(processed, &elem(&1, 0))
    key_vars = Enum.map(processed, &elem(&1, 1))
    impl_args = Enum.map(processed, &elem(&1, 2))

    quote do
      def unquote({name, name_meta, outer_args}) do
        cache_key = {__MODULE__, unquote(name), [unquote_splicing(key_vars)]}

        case SimpleSyllabusReporter.Cache.get(cache_key) do
          {:ok, cached} ->
            {:ok, cached}

          :miss ->
            case unquote(impl_name)(unquote_splicing(key_vars)) do
              {:ok, value} = result ->
                SimpleSyllabusReporter.Cache.put(cache_key, value)
                result

              other ->
                other
            end
        end
      end

      defp unquote({impl_name, name_meta, impl_args}) do
        unquote(body)
      end
    end
  end

  # --- GenServer callbacks ---

  @impl true
  def init(_) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    schedule_sweep()
    {:ok, []}
  end

  @impl true
  def handle_info(:sweep, state) do
    now = System.monotonic_time(:millisecond)
    :ets.select_delete(@table, [{{:_, :_, :"$1"}, [{:<, :"$1", now}], [true]}])
    schedule_sweep()
    {:noreply, state}
  end

  defp schedule_sweep do
    Process.send_after(self(), :sweep, @sweep_interval)
  end
end
