alias Experimental.Flow

defmodule Flow.Window.Test do
  use ExUnit.Case, async: true

  doctest Flow.Window

  describe "global window" do
    test "trigger keep with large demand" do
      assert Flow.from_enumerable(1..100)
             |> Flow.partition(stages: 1)
             |> Flow.window(Flow.Window.global |> Flow.Window.trigger_every(10))
             |> Flow.reduce(fn -> 0 end, & &1 + &2)
             |> Flow.emit(:state)
             |> Enum.to_list() == [55, 210, 465, 820, 1275, 1830, 2485, 3240, 4095, 5050, 5050]
    end

    test "trigger keep with small demand" do
      assert Flow.from_enumerable(1..100)
             |> Flow.partition(stages: 1, max_demand: 5)
             |> Flow.window(Flow.Window.global |> Flow.Window.trigger_every(10))
             |> Flow.reduce(fn -> 0 end, & &1 + &2)
             |> Flow.emit(:state)
             |> Enum.to_list() == [55, 210, 465, 820, 1275, 1830, 2485, 3240, 4095, 5050, 5050]
    end

    test "trigger discard with large demand" do
      assert Flow.from_enumerable(1..100)
             |> Flow.partition(stages: 1)
             |> Flow.window(Flow.Window.global |> Flow.Window.trigger_every(10, :reset))
             |> Flow.reduce(fn -> 0 end, & &1 + &2)
             |> Flow.emit(:state)
             |> Enum.to_list() == [55, 155, 255, 355, 455, 555, 655, 755, 855, 955, 0]
    end

    test "trigger discard with small demand" do
      assert Flow.from_enumerable(1..100)
             |> Flow.partition(stages: 1, max_demand: 5)
             |> Flow.window(Flow.Window.global |> Flow.Window.trigger_every(10, :reset))
             |> Flow.reduce(fn -> 0 end, & &1 + &2)
             |> Flow.emit(:state)
             |> Enum.to_list() == [55, 155, 255, 355, 455, 555, 655, 755, 855, 955, 0]
    end

    test "trigger ordering" do
      window =
        Flow.Window.trigger(Flow.Window.global, fn -> true end, fn events, true ->
          {:cont, Enum.all?(events, &rem(&1, 2) == 0)}
        end)

      assert Flow.from_enumerable(1..10)
             |> Flow.partition(stages: 1)
             |> Flow.map(& &1 + 1)
             |> Flow.map(& &1 * 2)
             |> Flow.window(window)
             |> Flow.map(& div(&1, 2))
             |> Flow.map(& &1 + 1)
             |> Flow.reduce(fn -> 0 end, & &1 + &2)
             |> Flow.emit(:state)
             |> Enum.sort() == [75]
    end

    test "trigger names" do
      assert Flow.from_enumerable(1..100)
             |> Flow.partition(stages: 1)
             |> Flow.window(Flow.Window.global |> Flow.Window.trigger_every(10, :reset))
             |> Flow.reduce(fn -> 0 end, & &1 + &2)
             |> Flow.map_state(fn state, _, {:global, :global, trigger} -> {trigger, state} end)
             |> Flow.emit(:state)
             |> Enum.sort() == [{:done, 0},
                                {{:every, 10}, 55}, {{:every, 10}, 155},
                                {{:every, 10}, 255}, {{:every, 10}, 355},
                                {{:every, 10}, 455}, {{:every, 10}, 555},
                                {{:every, 10}, 655}, {{:every, 10}, 755},
                                {{:every, 10}, 855}, {{:every, 10}, 955}]
    end

    test "trigger based on intervals" do
      assert Flow.new(max_demand: 5, stages: 2)
             |> Flow.from_enumerable(Stream.concat(1..10, Stream.timer(:infinity)))
             |> Flow.partition(stages: 1, max_demand: 10)
             |> Flow.window(Flow.Window.global |> Flow.Window.trigger_periodically(200, :microseconds))
             |> Flow.reduce(fn -> 0 end, & &1 + &2)
             |> Flow.map_state(& &1 * 2)
             |> Flow.emit(:state)
             |> Enum.take(1) == [110]
    end

    test "trigger based on timers" do
      assert Flow.new(max_demand: 5, stages: 2)
             |> Flow.from_enumerable(Stream.concat(1..10, Stream.timer(:infinity)))
             |> Flow.partition(stages: 1, max_demand: 10)
             |> Flow.reduce(fn ->
                  Process.send_after(self(), {:trigger, :reset, :sample}, 200)
                  0
                end, & &1 + &2)
             |> Flow.map_state(&{&1 * 2, &2, &3})
             |> Flow.emit(:state)
             |> Enum.take(1) == [{110, {0, 1}, {:global, :global, :sample}}]
    end

    test "periodic triggers" do
      assert Flow.Window.global
             |> Flow.Window.trigger_periodically(10, :seconds, :keep)
             |> Map.fetch!(:periodically) ==
             [{10000, :keep, {:periodically, 10, :seconds}}]

      assert Flow.Window.global
             |> Flow.Window.trigger_periodically(10, :minutes, :keep)
             |> Map.fetch!(:periodically) ==
             [{600000, :keep, {:periodically, 10, :minutes}}]

      assert Flow.Window.global
             |> Flow.Window.trigger_periodically(10, :hours, :keep)
             |> Map.fetch!(:periodically) ==
             [{36000000, :keep, {:periodically, 10, :hours}}]
    end
  end
end
