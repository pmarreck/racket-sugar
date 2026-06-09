# Elixir's BUILT-IN Enum.sort/1 (an optimized merge sort), over the same MINSTD data.
# The "more fair" Elixir comparison: this is what real Elixir code uses, not a
# hand-rolled functional quicksort.
defmodule D do
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
D.make_data(n, 42) |> Enum.sort() |> D.checksum() |> IO.puts()
