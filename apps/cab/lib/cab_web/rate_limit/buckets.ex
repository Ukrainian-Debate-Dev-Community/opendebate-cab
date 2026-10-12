defmodule CabWeb.RateLimit.Buckets do
  @moduledoc """
  The token buckets behind CabWeb.RateLimit, in one GenServer's state:
  one process, no table to share; buckets idle long enough to be full
  again are dropped every few minutes.
  """
  use GenServer

  @prune_every :timer.minutes(5)

  def start_link(_opts), do: GenServer.start_link(__MODULE__, %{}, name: __MODULE__)

  @doc """
  Takes one token from the caller's bucket: `{:ok, remaining, seconds
  until full}` or `{:error, seconds until the next token}`.
  """
  def take(key, per_minute, burst) do
    GenServer.call(
      __MODULE__,
      {:take, key, per_minute, burst, System.monotonic_time(:millisecond)}
    )
  end

  @doc "Empties every bucket (tests)."
  def reset, do: GenServer.call(__MODULE__, :reset)

  @impl GenServer
  def init(buckets) do
    Process.send_after(self(), :prune, @prune_every)
    {:ok, buckets}
  end

  @impl GenServer
  def handle_call({:take, key, per_minute, burst, now}, _from, buckets) do
    rate = per_minute / 60_000
    {tokens, last} = Map.get(buckets, key, {burst * 1.0, now})
    tokens = min(burst * 1.0, tokens + (now - last) * rate)

    if tokens >= 1 do
      left = tokens - 1
      full_in = ceil((burst - left) / rate / 1000)
      {:reply, {:ok, trunc(left), full_in}, Map.put(buckets, key, {left, now})}
    else
      retry = max(1, ceil((1 - tokens) / rate / 1000))
      {:reply, {:error, retry}, Map.put(buckets, key, {tokens, now})}
    end
  end

  def handle_call(:reset, _from, _buckets), do: {:reply, :ok, %{}}

  @impl GenServer
  def handle_info(:prune, buckets) do
    now = System.monotonic_time(:millisecond)
    # a bucket idle for ten minutes is full again in every setting we use
    buckets =
      Map.reject(buckets, fn {_key, {_tokens, last}} -> now - last > :timer.minutes(10) end)

    Process.send_after(self(), :prune, @prune_every)
    {:noreply, buckets}
  end
end
