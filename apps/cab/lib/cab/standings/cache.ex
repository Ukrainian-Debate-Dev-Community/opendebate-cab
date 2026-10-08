defmodule Cab.Standings.Cache do
  @moduledoc """
  ETS cache for standings of FINISHED sessions only — a completed
  engine event is immutable, so its standings never change (rule 0:
  the cached rows are the engine's verbatim output). Live data must
  never pass through here.

  `flush/0` is the operator handle (remote console / release command);
  the beta ops round wires it to a make target.
  """
  use GenServer

  @table :cab_standings_cache

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    :ets.new(@table, [:named_table, :public, read_concurrency: true])
    {:ok, nil}
  end

  @doc """
  Returns the cached value for `key`, or runs `fun` and caches it.
  `fun` returns `{:commit, value}` to cache or `{:ignore, value}` to
  pass through uncached (engine errors must not stick).
  """
  def fetch(key, fun) do
    if enabled?(), do: lookup(key, fun), else: passthrough(fun)
  end

  defp enabled?, do: Application.get_env(:cab, :standings_cache, true)

  defp passthrough(fun) do
    case fun.() do
      {:commit, value} -> value
      {:ignore, value} -> value
    end
  end

  defp lookup(key, fun) do
    case :ets.lookup(@table, key) do
      [{^key, value}] ->
        value

      [] ->
        case fun.() do
          {:commit, value} ->
            :ets.insert(@table, {key, value})
            value

          {:ignore, value} ->
            value
        end
    end
  end

  def flush, do: :ets.delete_all_objects(@table)
end
