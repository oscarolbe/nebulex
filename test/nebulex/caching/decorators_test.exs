defmodule Nebulex.Caching.DecoratorsTest do
  use ExUnit.Case, async: true
  use Nebulex.Caching.Decorators

  defmodule Cache do
    use Nebulex.Cache,
      otp_app: :nebulex,
      adapter: Nebulex.Adapters.Local
  end

  defmodule Meta do
    defstruct [:id, :count]
  end

  alias Nebulex.Caching.DecoratorsTest.{Cache, Meta}

  setup do
    {:ok, pid} = Cache.start_link(n_generations: 2)
    :ok

    on_exit(fn ->
      :ok = Process.sleep(10)
      if Process.alive?(pid), do: Cache.stop(pid)
    end)
  end

  test "fail on cacheable because missing cache" do
    assert_raise ArgumentError, "expected cache: to be given as argument", fn ->
      defmodule Test do
        use Nebulex.Caching.Decorators

        @decorate cache(a: 1)
        def t(a, b) do
          {a, b}
        end
      end
    end
  end

  test "cache" do
    refute Cache.get("x")
    assert {"x", "y"} == get_by_x("x")
    assert {"x", "y"} == Cache.get("x")

    refute Cache.get({"x", "y"})
    assert {"x", "y"} == get_by_xy("x", "y")
    assert {"x", "y"} == Cache.get({"x", "y"})

    :ok = Process.sleep(1100)
    assert {"x", "y"} == Cache.get("x")
    assert {"x", "y"} == Cache.get({"x", "y"})
  end

  test "cache with opts" do
    refute Cache.get("x")
    assert 1 == get_with_opts(1)
    assert 1 == Cache.get(1)

    :ok = Process.sleep(1100)
    refute Cache.get(1)
  end

  test "cache with match" do
    refute Cache.get(:x)
    assert :x == get_with_match(:x)
    refute Cache.get(:x)

    refute Cache.get(:y)
    assert :y == get_with_match(:y)
    assert Cache.get(:y)

    refute Cache.get(:ok)
    assert :ok == get_with_match2(:ok)
    assert Cache.get(:ok)

    refute Cache.get(:error)
    assert :error == get_with_match2(:error)
    refute Cache.get(:error)
  end

  test "cache with default key" do
    key = :erlang.phash2({__MODULE__, :get_with_default_key})

    refute Cache.get(key)
    assert :ok == get_with_default_key(123, {:foo, "bar"})
    assert :ok == Cache.get(key)
    assert :ok == get_with_default_key(:foo, "bar")
    assert :ok == Cache.get(key)
  end

  test "defining keys using structs and maps" do
    refute Cache.get("x")
    assert %Meta{id: 1, count: 1} == get_meta(%Meta{id: 1, count: 1})
    assert %Meta{id: 1, count: 1} == Cache.get({Meta, 1})

    refute Cache.get("y")
    assert %{id: 1} == get_map(%{id: 1})
    assert %{id: 1} == Cache.get(1)
  end

  test "evict" do
    assert :ok == set_keys(x: 1, y: 2, z: 3)

    assert :x == cache_evict(:x)
    refute Cache.get(:x)
    assert 2 == Cache.get(:y)
    assert 3 == Cache.get(:z)

    assert :y == cache_evict(:y)
    refute Cache.get(:x)
    refute Cache.get(:y)
    assert 3 == Cache.get(:z)
  end

  test "evict with multiple keys" do
    assert :ok == set_keys(x: 1, y: 2, z: 3)
    assert {:x, :y} == cache_evict_keys(:x, :y)
    refute Cache.get(:x)
    refute Cache.get(:y)
    assert 3 == Cache.get(:z)
  end

  test "evict all entries" do
    assert :ok == set_keys(x: 1, y: 2, z: 3)
    assert "hello" == cache_evict_all("hello")
    refute Cache.get(:x)
    refute Cache.get(:y)
    refute Cache.get(:z)
  end

  test "update" do
    assert :ok == set_keys(x: 1, y: 2, z: 3)
    assert :x == cache_put(:x)
    assert :y == cache_put(:y)
    assert :x == Cache.get(:x)
    assert :y == Cache.get(:y)
    assert 3 == Cache.get(:z)

    :ok = Process.sleep(1100)
    assert :x == Cache.get(:x)
    assert :y == Cache.get(:y)
    assert 3 == Cache.get(:z)
  end

  test "update with opts" do
    assert :ok == set_keys(x: 1, y: 2, z: 3)
    assert :x == cache_put_with_opts(:x)
    assert :y == cache_put_with_opts(:y)

    :ok = Process.sleep(1100)
    refute Cache.get(:x)
    refute Cache.get(:y)
  end

  test "update with match" do
    assert :ok == set_keys(x: 0, y: 0, z: 0)
    assert :x == cache_put_with_match(:x)
    assert :y == cache_put_with_match(:y)
    assert 0 == Cache.get(:x)
    assert :y == Cache.get(:y)
  end

  ## Caching Functions

  @decorate cache(cache: Cache, key: x)
  def get_by_x(x, y \\ "y") do
    {x, y}
  end

  @decorate cache(cache: Cache, key: x, opts: [ttl: 1])
  def get_with_opts(x) do
    x
  end

  @decorate cache(cache: Cache, key: x, match: fn x -> x != :x end)
  def get_with_match(x) do
    x
  end

  @decorate cache(cache: Cache, key: x, match: &match/1)
  def get_with_match2(x) do
    x
  end

  defp match(:ok), do: true
  defp match(_), do: false

  @decorate cache(cache: Cache, key: {x, y})
  def get_by_xy(x, y) do
    {x, y}
  end

  @decorate cache(cache: Cache)
  def get_with_default_key(x, y) do
    _ = {x, y}
    :ok
  end

  @decorate cache(cache: Cache, key: {Meta, meta.id})
  def get_meta(%Meta{} = meta) do
    meta
  end

  @decorate cache(cache: Cache, key: map[:id])
  def get_map(map) do
    map
  end

  @decorate evict(cache: Cache, key: x)
  def cache_evict(x) do
    x
  end

  @decorate evict(cache: Cache, keys: [x, y])
  def cache_evict_keys(x, y) do
    {x, y}
  end

  @decorate evict(cache: Cache, all_entries: true)
  def cache_evict_all(x) do
    x
  end

  @decorate update(cache: Cache, key: x)
  def cache_put(x) do
    x
  end

  @decorate update(cache: Cache, key: x, opts: [ttl: 1])
  def cache_put_with_opts(x) do
    x
  end

  @decorate update(cache: Cache, key: x, match: fn x -> x != :x end)
  def cache_put_with_match(x) do
    x
  end

  ## Private Functions

  defp set_keys(entries) do
    assert :ok == Cache.set_many(entries)

    Enum.each(entries, fn {k, v} ->
      assert v == Cache.get(k)
    end)
  end
end
