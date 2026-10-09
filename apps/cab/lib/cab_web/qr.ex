defmodule CabWeb.QR do
  @moduledoc """
  A QR code encoder for short links: byte mode, error correction
  level M, versions 1-10 (up to 213 bytes). `matrix/1` returns rows of
  booleans, dark = true, without the quiet zone; the room card draws
  it on a canvas.

  Follows ISO/IEC 18004: Reed-Solomon over GF(256) (polynomial 0x11D),
  block interleaving, function patterns, zigzag placement, and the
  mask with the lowest penalty score.
  """

  import Bitwise

  # version => {ec codewords per block, [{block count, data codewords}]}
  @blocks %{
    1 => {10, [{1, 16}]},
    2 => {16, [{1, 28}]},
    3 => {26, [{1, 44}]},
    4 => {18, [{2, 32}]},
    5 => {24, [{2, 43}]},
    6 => {16, [{4, 27}]},
    7 => {18, [{4, 31}]},
    8 => {22, [{2, 38}, {2, 39}]},
    9 => {22, [{3, 36}, {2, 37}]},
    10 => {26, [{4, 43}, {1, 44}]}
  }

  @alignment %{
    1 => [],
    2 => [6, 18],
    3 => [6, 22],
    4 => [6, 26],
    5 => [6, 30],
    6 => [6, 34],
    7 => [6, 22, 38],
    8 => [6, 24, 42],
    9 => [6, 26, 46],
    10 => [6, 28, 50]
  }

  # GF(256) tables
  {exp, log} =
    Enum.reduce(0..254, {%{}, %{}, 1}, fn i, {exp, log, x} ->
      next = x <<< 1
      next = if next > 255, do: bxor(next, 0x11D), else: next
      {Map.put(exp, i, x), Map.put(log, x, i), next}
    end)
    |> then(fn {exp, log, _} -> {exp, log} end)

  @exp exp
  @log log

  @doc "The QR matrix for `text`, or `{:error, :too_long}` beyond version 10."
  def matrix(text) when is_binary(text) do
    with {:ok, version} <- pick_version(byte_size(text)) do
      codewords = text |> data_codewords(version) |> interleave(version)
      size = version * 4 + 17
      {base, function} = function_patterns(version, size)
      placed = place(base, function, codewords, size)

      {_penalty, best} =
        0..7
        |> Enum.map(fn mask ->
          grid = placed |> apply_mask(function, mask, size) |> draw_format(mask, size)
          {penalty(grid, size), grid}
        end)
        |> Enum.min_by(&elem(&1, 0))

      for y <- 0..(size - 1), do: for(x <- 0..(size - 1), do: Map.get(best, {x, y}, false))
    end
  end

  @doc false
  # the same matrix with a forced mask (reference checks)
  def matrix(text, mask) when mask in 0..7 do
    with {:ok, version} <- pick_version(byte_size(text)) do
      codewords = text |> data_codewords(version) |> interleave(version)
      size = version * 4 + 17
      {base, function} = function_patterns(version, size)

      grid =
        base
        |> place(function, codewords, size)
        |> apply_mask(function, mask, size)
        |> draw_format(mask, size)

      for y <- 0..(size - 1), do: for(x <- 0..(size - 1), do: Map.get(grid, {x, y}, false))
    end
  end

  defp data_capacity(version) do
    {_ec, groups} = @blocks[version]
    Enum.sum(for {count, data} <- groups, do: count * data)
  end

  defp pick_version(bytes) do
    Enum.find_value(1..10, {:error, :too_long}, fn version ->
      count_bits = if version < 10, do: 8, else: 16
      if 4 + count_bits + bytes * 8 <= data_capacity(version) * 8, do: {:ok, version}
    end)
  end

  # mode, count, data, terminator, byte padding, pad codewords
  defp data_codewords(text, version) do
    count_bits = if version < 10, do: 8, else: 16
    capacity = data_capacity(version) * 8
    bits = <<0b0100::4, byte_size(text)::size(count_bits), text::binary>>
    used = bit_size(bits)
    terminator = min(4, capacity - used)
    bits = <<bits::bitstring, 0::size(terminator)>>
    pad = rem(8 - rem(bit_size(bits), 8), 8)
    bytes = for <<(b::8 <- <<bits::bitstring, 0::size(pad)>>)>>, do: b
    fill = div(capacity, 8) - length(bytes)
    bytes ++ Enum.take(Stream.cycle([0xEC, 0x11]), fill)
  end

  defp interleave(data, version) do
    {ec_len, groups} = @blocks[version]

    {blocks, []} =
      Enum.reduce(groups, {[], data}, fn {count, len}, {acc, rest} ->
        Enum.reduce(1..count, {acc, rest}, fn _, {acc, rest} ->
          {block, rest} = Enum.split(rest, len)
          {acc ++ [block], rest}
        end)
      end)

    ecs = Enum.map(blocks, &reed_solomon(&1, ec_len))
    columns(blocks) ++ columns(ecs)
  end

  defp columns(blocks) do
    longest = blocks |> Enum.map(&length/1) |> Enum.max()

    for i <- 0..(longest - 1), block <- blocks, i < length(block), do: Enum.at(block, i)
  end

  defp gf_mul(0, _b), do: 0
  defp gf_mul(_a, 0), do: 0
  defp gf_mul(a, b), do: @exp[rem(@log[a] + @log[b], 255)]

  defp generator(degree) do
    Enum.reduce(0..(degree - 1), [1], fn i, poly ->
      root = @exp[i]
      shifted = poly ++ [0]
      scaled = [0 | Enum.map(poly, &gf_mul(&1, root))]
      Enum.zip_with(shifted, scaled, &bxor/2)
    end)
  end

  defp reed_solomon(data, ec_len) do
    [_lead | gen] = generator(ec_len)

    Enum.reduce(data, List.duplicate(0, ec_len), fn byte, remainder ->
      factor = bxor(byte, hd(remainder))
      shifted = tl(remainder) ++ [0]
      Enum.zip_with(shifted, gen, fn r, g -> bxor(r, gf_mul(g, factor)) end)
    end)
  end

  # timing, finders (with separators), alignment, dark module, reserved
  # format and version areas; `function` marks every fixed module
  defp function_patterns(version, size) do
    grid = %{}
    function = MapSet.new()

    set = fn {grid, function}, x, y, dark ->
      {Map.put(grid, {x, y}, dark), MapSet.put(function, {x, y})}
    end

    acc =
      Enum.reduce(0..(size - 1), {grid, function}, fn i, acc ->
        acc |> set.(6, i, rem(i, 2) == 0) |> set.(i, 6, rem(i, 2) == 0)
      end)

    acc =
      Enum.reduce([{3, 3}, {size - 4, 3}, {3, size - 4}], acc, fn {cx, cy}, acc ->
        for(dy <- -4..4, dx <- -4..4, do: {dx, dy})
        |> Enum.reduce(acc, fn {dx, dy}, acc ->
          {x, y} = {cx + dx, cy + dy}
          dist = max(abs(dx), abs(dy))

          if x in 0..(size - 1) and y in 0..(size - 1),
            do: set.(acc, x, y, dist != 2 and dist != 4),
            else: acc
        end)
      end)

    positions = @alignment[version]
    last = length(positions) - 1

    acc =
      for(
        {px, i} <- Enum.with_index(positions),
        {py, j} <- Enum.with_index(positions),
        not ((i == 0 and j == 0) or (i == 0 and j == last) or (i == last and j == 0)),
        do: {px, py}
      )
      |> Enum.reduce(acc, fn {cx, cy}, acc ->
        for(dy <- -2..2, dx <- -2..2, do: {dx, dy})
        |> Enum.reduce(acc, fn {dx, dy}, acc ->
          set.(acc, cx + dx, cy + dy, max(abs(dx), abs(dy)) != 1)
        end)
      end)

    # reserve the format areas (drawn per mask later)
    acc =
      Enum.reduce(format_positions(size), acc, fn {x, y}, acc -> set.(acc, x, y, false) end)

    acc = set.(acc, 8, size - 8, true)

    acc =
      if version >= 7 do
        bits = version_bits(version)

        Enum.reduce(0..17, acc, fn i, acc ->
          dark = (bits >>> i &&& 1) == 1
          a = size - 11 + rem(i, 3)
          b = div(i, 3)
          acc |> set.(a, b, dark) |> set.(b, a, dark)
        end)
      else
        acc
      end

    acc
  end

  defp version_bits(version) do
    rem =
      Enum.reduce(1..12, version, fn _, r ->
        bxor(r <<< 1, (r >>> 11) * 0x1F25)
      end)

    version <<< 12 ||| (rem &&& 0xFFF)
  end

  # the 15 format bit positions of both copies, in bit order
  defp format_first,
    do:
      Enum.map(0..5, &{8, &1}) ++
        [{8, 7}, {8, 8}, {7, 8}] ++ Enum.map(9..14, &{14 - &1, 8})

  defp format_second(size),
    do: Enum.map(0..7, &{size - 1 - &1, 8}) ++ Enum.map(8..14, &{8, size - 15 + &1})

  defp format_positions(size), do: format_first() ++ format_second(size)

  defp place(grid, function, codewords, size) do
    bits = for byte <- codewords, i <- 7..0//-1, do: (byte >>> i &&& 1) == 1

    order =
      for right <-
            Enum.map((size - 1)..1//-2, &if(&1 <= 6, do: &1 - 1, else: &1)),
          vert <- 0..(size - 1),
          j <- 0..1,
          x = right - j,
          # the column pair's direction alternates: up, down, up, ...
          y = if((right + 1 &&& 2) == 0, do: size - 1 - vert, else: vert),
          not MapSet.member?(function, {x, y}),
          do: {x, y}

    {grid, _rest} =
      Enum.reduce(order, {grid, bits}, fn
        pos, {grid, [bit | rest]} -> {Map.put(grid, pos, bit), rest}
        pos, {grid, []} -> {Map.put(grid, pos, false), []}
      end)

    grid
  end

  defp apply_mask(grid, function, mask, size) do
    for y <- 0..(size - 1), x <- 0..(size - 1), into: grid do
      dark = Map.get(grid, {x, y}, false)

      if MapSet.member?(function, {x, y}),
        do: {{x, y}, dark},
        else: {{x, y}, if(masked?(mask, x, y), do: not dark, else: dark)}
    end
  end

  defp masked?(0, x, y), do: rem(x + y, 2) == 0
  defp masked?(1, _x, y), do: rem(y, 2) == 0
  defp masked?(2, x, _y), do: rem(x, 3) == 0
  defp masked?(3, x, y), do: rem(x + y, 3) == 0
  defp masked?(4, x, y), do: rem(div(x, 3) + div(y, 2), 2) == 0
  defp masked?(5, x, y), do: rem(x * y, 2) + rem(x * y, 3) == 0
  defp masked?(6, x, y), do: rem(rem(x * y, 2) + rem(x * y, 3), 2) == 0
  defp masked?(7, x, y), do: rem(rem(x + y, 2) + rem(x * y, 3), 2) == 0

  # level M = 0b00
  defp draw_format(grid, mask, size) do
    data = mask
    rem = Enum.reduce(1..10, data, fn _, r -> bxor(r <<< 1, (r >>> 9) * 0x537) end)
    bits = bxor(data <<< 10 ||| (rem &&& 0x3FF), 0x5412)

    grid =
      format_first()
      |> Enum.with_index()
      |> Enum.reduce(grid, fn {pos, i}, g -> Map.put(g, pos, (bits >>> i &&& 1) == 1) end)

    format_second(size)
    |> Enum.with_index()
    |> Enum.reduce(grid, fn {pos, i}, g -> Map.put(g, pos, (bits >>> i &&& 1) == 1) end)
    |> Map.put({8, size - 8}, true)
  end

  # ISO penalty rules N1-N4
  defp penalty(grid, size) do
    rows = for y <- 0..(size - 1), do: for(x <- 0..(size - 1), do: grid[{x, y}])
    cols = for x <- 0..(size - 1), do: for(y <- 0..(size - 1), do: grid[{x, y}])
    lines = rows ++ cols

    n1 =
      lines
      |> Enum.flat_map(&Enum.chunk_by(&1, fn v -> v end))
      |> Enum.map(&length/1)
      |> Enum.filter(&(&1 >= 5))
      |> Enum.map(&(&1 - 2))
      |> Enum.sum()

    n2 =
      Enum.count(
        for(x <- 0..(size - 2), y <- 0..(size - 2), do: {x, y}),
        fn {x, y} ->
          v = grid[{x, y}]
          grid[{x + 1, y}] == v and grid[{x, y + 1}] == v and grid[{x + 1, y + 1}] == v
        end
      ) * 3

    a = [true, false, true, true, true, false, true, false, false, false, false]
    b = Enum.reverse(a)

    n3 =
      lines
      |> Enum.map(fn line ->
        line
        |> Enum.chunk_every(11, 1, :discard)
        |> Enum.count(&(&1 == a or &1 == b))
      end)
      |> Enum.sum()
      |> Kernel.*(40)

    dark = Enum.count(rows |> List.flatten(), & &1)
    total = size * size
    n4 = div(abs(dark * 20 - total * 10), total) * 10

    n1 + n2 + n3 + n4
  end
end
