# Quicksort in Elixir — idiomatic functional, immutable list (like the Racket version).
# Same MINSTD input + order-dependent checksum as the other implementations.
defmodule QS do
  def sort([]), do: []
  def sort([pivot | rest]) do
    {lt, gte} = Enum.split_with(rest, fn x -> x < pivot end)
    sort(lt) ++ [pivot | sort(gte)]
  end

  def make_data(n, seed) do
    Stream.iterate(seed, fn x -> rem(48271 * x, 2147483647) end)
    |> Stream.drop(1)
    |> Enum.take(n)
  end

  def checksum(list) do
    list
    |> Enum.with_index(1)
    |> Enum.reduce(0, fn {v, i}, acc -> rem(acc + i * v, 1000000007) end)
  end
end

[n_str | _] = System.argv()
n = String.to_integer(n_str)
QS.make_data(n, 42) |> QS.sort() |> QS.checksum() |> IO.puts()
