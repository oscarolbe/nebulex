defmodule Nebulex.LocalTest do
  import Nebulex.SharedTestCase

  deftests do
    import Ex2ms
    import Nebulex.CacheHelpers

    setup do
      {:ok, pid} = @cache.start_link(n_generations: 2)
      :ok

      on_exit(fn ->
        :ok = Process.sleep(10)
        if Process.alive?(pid), do: @cache.stop(pid)
      end)
    end

    test "fail on before_compile because invalid backend" do
      msg = "supported backends: [:ets, :shards], got: :xyz"

      assert_raise ArgumentError, msg, fn ->
        defmodule MyCache do
          use Nebulex.Cache,
            otp_app: :nebulex,
            adapter: Nebulex.Adapters.Local,
            backend: :xyz
        end
      end
    end

    test "fail with ArgumentError because cache was stopped" do
      :ok =
        @cache
        |> Process.whereis()
        |> @cache.stop()

      assert_raise ArgumentError, fn -> @cache.put(1, 13) end
      assert_raise ArgumentError, fn -> @cache.get(1) end
      assert_raise ArgumentError, fn -> @cache.delete(1) end
    end

    test "get_and_update" do
      assert {nil, 1} ==
               @cache.get_and_update(1, fn
                 nil -> {nil, 1}
                 val -> {val, val * 2}
               end)

      assert {1, 2} == @cache.get_and_update(1, &{&1, &1 * 2})
      assert {2, 6} == @cache.get_and_update(1, &{&1, &1 * 3})
      assert {6, nil} == @cache.get_and_update(1, &{&1, nil})
      assert 6 == @cache.get(1)
      assert {6, nil} == @cache.get_and_update(1, fn _ -> :pop end)
      assert {nil, 3} == @cache.get_and_update(3, &{&1, 3})

      assert_raise ArgumentError, fn ->
        @cache.get_and_update(1, fn _ -> :other end)
      end
    end

    test "incr with update" do
      assert 1 == @cache.incr(:counter)
      assert 2 == @cache.incr(:counter)

      assert {2, 4} == @cache.get_and_update(:counter, &{&1, &1 * 2})
      assert 5 == @cache.incr(:counter)

      assert 10 == @cache.update(:counter, 1, &(&1 * 2))
      assert 0 == @cache.incr(:counter, -10)

      assert :ok == @cache.put("foo", "bar")

      assert_raise ArgumentError, fn ->
        @cache.incr("foo")
      end
    end

    test "incr with ttl" do
      assert 1 == @cache.incr(:counter_with_ttl, 1, ttl: 1000)
      assert 2 == @cache.incr(:counter_with_ttl)
      assert 2 == @cache.get(:counter_with_ttl)
      :ok = Process.sleep(1010)
      refute @cache.get(:counter_with_ttl)

      assert 1 == @cache.incr(:counter_with_ttl, 1, ttl: 5000)
      assert @cache.ttl(:counter_with_ttl) > 1000

      assert @cache.expire(:counter_with_ttl, 500)
      :ok = Process.sleep(600)
      refute @cache.get(:counter_with_ttl)
    end

    test "incr over an existing entry" do
      assert :ok == @cache.put(:counter, 0)
      assert 1 == @cache.incr(:counter)
      assert 3 == @cache.incr(:counter, 2)
    end

    test "all and stream using match_spec queries" do
      values = cache_put(@cache, 1..5, &(&1 * 2))
      _ = @cache.new_generation()
      values = values ++ cache_put(@cache, 6..10, &(&1 * 2))

      assert values ==
               nil
               |> @cache.stream(page_size: 3, return: :value)
               |> Enum.to_list()
               |> :lists.usort()

      {_, expected} = Enum.split(values, 5)

      test_ms =
        fun do
          {_, _, value, _, _} when value > 10 -> value
        end

      for action <- [:all, :stream] do
        assert expected == all_or_stream(action, test_ms, page_size: 3, return: :value)

        msg = ~r"invalid match spec"

        assert_raise Nebulex.QueryError, msg, fn ->
          all_or_stream(action, :invalid_query)
        end
      end
    end

    test "all and stream using expired and unexpired queries" do
      for action <- [:all, :stream] do
        expired = cache_put(@cache, 1..5, &(&1 * 2), ttl: 1000)
        unexpired = cache_put(@cache, 6..10, &(&1 * 2))

        all = expired ++ unexpired

        opts = [page_size: 3, return: :value]

        assert all == all_or_stream(action, nil, opts)
        assert all == all_or_stream(action, :unexpired, opts)
        assert [] == all_or_stream(action, :expired, opts)

        :ok = Process.sleep(1100)

        assert unexpired == all_or_stream(action, :unexpired, opts)
        assert expired == all_or_stream(action, :expired, opts)
      end
    end

    test "unexpired entries through generations" do
      assert :ok == @cache.put("foo", "bar")
      assert "bar" == @cache.get("foo")
      assert :infinity == @cache.ttl("foo")

      _ = @cache.new_generation()
      assert "bar" == @cache.get("foo")
    end

    test "push generations" do
      # should be empty
      refute @cache.get(1)

      # set some entries
      for x <- 1..2, do: @cache.put(x, x)

      # fetch one entry from new generation
      assert 1 == @cache.get(1)

      # fetch non-existent entries
      refute @cache.get(3)
      refute @cache.get(:non_existent)

      # create a new generation
      _ = @cache.new_generation()

      # both entries should be in the old generation
      refute get_from_new(1)
      refute get_from_new(2)
      assert 1 == get_from_old(1)
      assert 2 == get_from_old(2)

      # fetch entry 1 to set it into the new generation
      assert 1 == @cache.get(1)
      assert 1 == get_from_new(1)
      refute get_from_new(2)
      refute get_from_old(1)
      assert 2 == get_from_old(2)

      # create a new generation, the old generation should be deleted
      _ = @cache.new_generation()

      # entry 1 should be into the old generation and entry 2 deleted
      refute get_from_new(1)
      refute get_from_new(2)
      assert 1 == get_from_old(1)
      refute get_from_old(2)
    end

    test "push generations with ttl" do
      assert :ok == @cache.put(1, 1, ttl: 1000)
      assert 1 == @cache.get(1)

      _ = @cache.new_generation()

      refute get_from_new(1)
      assert 1 == get_from_old(1)
      assert 1 == @cache.get(1)

      :ok = Process.sleep(1100)

      refute @cache.get(1)
      refute get_from_new(1)
      refute get_from_old(1)
    end

    ## Helpers

    defp get_from_new(key) do
      @cache.__metadata__().generations
      |> hd()
      |> get_from(key)
    end

    defp get_from_old(key) do
      @cache.__metadata__().generations
      |> List.last()
      |> get_from(key)
    end

    defp get_from(gen, key) do
      case @cache.__backend__().lookup(gen, key) do
        [] -> nil
        [{_, ^key, val, _, _}] -> val
      end
    end

    defp all_or_stream(action, ms, opts \\ []) do
      @cache
      |> apply(action, [ms, opts])
      |> case do
        list when is_list(list) ->
          :lists.usort(list)

        stream ->
          stream
          |> Enum.to_list()
          |> :lists.usort()
      end
    end
  end
end