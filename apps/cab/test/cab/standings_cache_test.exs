defmodule Cab.Standings.CacheTest do
  use ExUnit.Case, async: false

  alias Cab.Standings.Cache

  setup do
    original = Application.get_env(:cab, :standings_cache)
    Application.put_env(:cab, :standings_cache, true)
    Cache.flush()

    on_exit(fn ->
      Cache.flush()
      Application.put_env(:cab, :standings_cache, original)
    end)
  end

  test "commit caches, ignore does not, flush clears" do
    key = {999_001, :teams}

    assert Cache.fetch(key, fn -> {:commit, [:rows]} end) == [:rows]
    # second read never runs the fun
    assert Cache.fetch(key, fn -> raise "must not run" end) == [:rows]

    # engine trouble passes through uncached
    miss = {999_002, :teams}
    assert Cache.fetch(miss, fn -> {:ignore, []} end) == []
    assert Cache.fetch(miss, fn -> {:commit, [:later]} end) == [:later]

    Cache.flush()
    assert Cache.fetch(key, fn -> {:commit, [:fresh]} end) == [:fresh]
  end
end
