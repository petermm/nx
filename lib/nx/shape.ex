defmodule Nx.Shape do
  # Conveniences for manipulating shapes.
  # Typically called from `Nx`.
  @moduledoc false

  @doc """
  Validates the names of axes.
  """
  def named_axes!(names, shape) do
    n_dims = tuple_size(shape)

    if names do
      n_names = length(names)

      if n_names != n_dims do
        raise ArgumentError,
              "invalid names for tensor of rank #{n_dims}," <>
                " when specifying names every dimension must" <>
                " have a name or be nil"
      else
        names
      end
    else
      List.duplicate(nil, n_dims)
    end
  end

  @doc """
  Broadcasts a shape to a new shape.

  The dimensions of `shape` is expanded to match the
  dimensions of `new_shape` according to the axes
  mapping.

  ## Examples

  ### Scalars

      iex> Nx.Shape.broadcast!({}, {4, 2, 1, 5}, [])
      :ok

      iex> Nx.Shape.broadcast!({}, {}, [])
      :ok

  ### n-D shapes

      iex> Nx.Shape.broadcast!({1}, {2, 3, 4}, [2])
      :ok

      iex> Nx.Shape.broadcast!({4, 2, 3}, {4, 3, 4, 2, 3}, [2, 3, 4])
      :ok

  ### Custom axes

      iex> Nx.Shape.broadcast!({2}, {2, 3}, [0])
      :ok

  ### Error cases

      iex> Nx.Shape.broadcast!({4, 2, 2}, {1, 1}, [0, 1, 2])
      ** (ArgumentError) cannot broadcast tensor of dimensions {4, 2, 2} to {1, 1} with axes [0, 1, 2]

      iex> Nx.Shape.broadcast!({2, 2}, {2, 2, 2}, [1, 0])
      ** (ArgumentError) broadcast axes must be ordered, got 0 after 1
  """
  def broadcast!(old_shape, new_shape, axes)

  def broadcast!(old_shape, new_shape, axes)
      when is_tuple(old_shape) and is_tuple(new_shape) and is_list(axes) do
    old_rank = tuple_size(old_shape)
    new_rank = tuple_size(new_shape)

    if length(axes) != old_rank do
      raise ArgumentError,
            "expected length of axes (#{length(axes)}) to match rank of shape (#{old_rank})"
    end

    if old_rank > new_rank or not valid_broadcast?(axes, 0, -1, old_shape, new_shape) do
      raise ArgumentError,
            "cannot broadcast tensor of dimensions #{inspect(old_shape)} " <>
              "to #{inspect(new_shape)} with axes #{inspect(axes)}"
    end

    :ok
  end

  defp valid_broadcast?([head | tail], axis, last, old_shape, new_shape) do
    if head < last do
      raise ArgumentError, "broadcast axes must be ordered, got #{head} after #{last}"
    end

    old_dim = elem(old_shape, axis)
    new_dim = elem(new_shape, head)

    (old_dim == 1 or old_dim == new_dim) and
      valid_broadcast?(tail, axis + 1, head, old_shape, new_shape)
  end

  defp valid_broadcast?([], _axis, _head, _old_shape, _new_shape), do: true

  @doc """
  Broadcasts two shapes to a common shape.

  The dimensions of either shape can be expanded to match
  the dimension of the other. This differs from a normal
  broadcast, where one shapes dimensions remain fixed,
  while the other's are expanded to match.

  ## Examples

  ### Scalar Shapes

      iex> Nx.Shape.binary_broadcast({}, [], {}, [])
      {{}, []}
      iex> Nx.Shape.binary_broadcast({}, [], {4, 2, 1, 5}, [:batch, nil, :data, nil])
      {{4, 2, 1, 5}, [:batch, nil, :data, nil]}

  ### n-D Shapes

      iex> Nx.Shape.binary_broadcast({8, 1, 6, 1}, [:batch, nil, :data, nil], {7, 1, 5}, [:time, :data, nil])
      {{8, 7, 6, 5}, [:batch, :time, :data, nil]}
      iex> Nx.Shape.binary_broadcast({7, 1, 5}, [:time, :data, nil], {8, 1, 6, 1},  [:batch, nil, :data, nil])
      {{8, 7, 6, 5}, [:batch, :time, :data, nil]}
      iex> Nx.Shape.binary_broadcast({5, 4}, [nil, nil], {1}, [:data])
      {{5, 4}, [nil, :data]}
      iex> Nx.Shape.binary_broadcast({3, 1}, [:x, :y], {15, 3, 5}, [:batch, :x, nil])
      {{15, 3, 5}, [:batch, :x, :y]}

  ### Error cases

      iex> Nx.Shape.binary_broadcast({4, 2, 5}, [nil, nil, nil], {3, 2, 5}, [:batch, :x, :y])
      ** (ArgumentError) cannot broadcast tensor of dimensions {4, 2, 5} to {3, 2, 5}

      iex> Nx.Shape.binary_broadcast({1, 2, 5}, [:batch, :x, :y], {3, 2, 5}, [:time, :x, :y])
      ** (ArgumentError) cannot merge names :batch, :time
  """
  def binary_broadcast(left_shape, left_names, right_shape, right_names)

  def binary_broadcast(shape, names, shape, names), do: {shape, names}

  def binary_broadcast(left_shape, left_names, right_shape, right_names)
      when is_tuple(left_shape) and is_tuple(right_shape) do
    left_rank = tuple_size(left_shape)
    right_rank = tuple_size(right_shape)
    rank = max(left_rank, right_rank)

    left_lower_and_names =
      shape_and_names_to_lower_ranked_list(
        left_shape,
        Enum.reverse(left_names),
        left_rank,
        rank
      )

    right_lower_and_names =
      shape_and_names_to_lower_ranked_list(
        right_shape,
        Enum.reverse(right_names),
        right_rank,
        rank
      )

    {left_lower, left_names} = Enum.unzip(left_lower_and_names)
    {right_lower, right_names} = Enum.unzip(right_lower_and_names)

    case binary_broadcast(left_lower, left_names, right_lower, right_names, [], []) do
      {:ok, new_shape, new_names} ->
        {new_shape, new_names}

      :error ->
        raise ArgumentError,
              "cannot broadcast tensor of dimensions #{inspect(left_shape)} " <>
                "to #{inspect(right_shape)}"
    end
  end

  defp binary_broadcast(
         [ldim | ldims],
         [lname | lnames],
         [rdim | rdims],
         [rname | rnames],
         shape_acc,
         names_acc
       )
       when rdim == 1 or ldim == 1 or rdim == ldim do
    names_acc = [merge_names!(lname, rname) | names_acc]
    binary_broadcast(ldims, lnames, rdims, rnames, [max(rdim, ldim) | shape_acc], names_acc)
  end

  defp binary_broadcast([], [], [], [], shape_acc, names_acc),
    do: {:ok, List.to_tuple(shape_acc), names_acc}

  defp binary_broadcast(_, _, _, _, _, _),
    do: :error

  defp shape_and_names_to_lower_ranked_list(_tuple, _names, 0, 0),
    do: []

  defp shape_and_names_to_lower_ranked_list(tuple, [], 0, rank),
    do: [{1, nil} | shape_and_names_to_lower_ranked_list(tuple, [], 0, rank - 1)]

  defp shape_and_names_to_lower_ranked_list(tuple, [n | names], size, rank),
    do: [
      {:erlang.element(size, tuple), n}
      | shape_and_names_to_lower_ranked_list(tuple, names, size - 1, rank - 1)
    ]

  @doc """
  Contracts a shape along the given axes.

  It expects the axes to have been normalized.

  ## Examples

      iex> Nx.Shape.contract({4, 1, 2}, [1], [:batch, :x, :y])
      {{4, 2}, [:batch, :y]}

      iex> Nx.Shape.contract({2, 4, 6, 5}, [1, 3], [:batch, :x, :y, :z])
      {{2, 6}, [:batch, :y]}

      iex> Nx.Shape.contract({1, 2, 3}, [], [:batch, :x, :y])
      {{1, 2, 3}, [:batch, :x, :y]}

      iex> Nx.Shape.contract({4, 2, 8}, [2], [:x, :y, :z])
      {{4, 2}, [:x, :y]}

  """
  def contract(shape, axes, names) do
    {new_shape, new_names} = Enum.unzip(contract(shape, axes, names, 0, tuple_size(shape)))
    {List.to_tuple(new_shape), new_names}
  end

  defp contract(_shape, _axes, _names, n, n) do
    []
  end

  defp contract(shape, axes, [name | names], i, n) do
    if i in axes do
      contract(shape, axes, names, i + 1, n)
    else
      [{elem(shape, i), name} | contract(shape, axes, names, i + 1, n)]
    end
  end

  @doc """
  Transposes a shape according to the given permutation.

  ## Examples

    iex> Nx.Shape.transpose({4, 8, 2, 1}, [1, 0, 3, 2], [:batch, :channels, :height, :width])
    {{8, 4, 1, 2}, [:channels, :batch, :width, :height]}

  ### Error cases

    iex> Nx.Shape.transpose({4, 8, 2, 1}, [0, 1, 2], [:batch, nil, nil, nil])
    ** (ArgumentError) expected length of permutation (3) to match rank of shape (4)

  """
  def transpose(shape, permutation, names)

  def transpose(shape, permutation, names) when tuple_size(shape) == length(permutation) do
    {new_shape, new_names} =
      Enum.unzip(Enum.map(permutation, &{elem(shape, &1), Enum.at(names, &1)}))

    {List.to_tuple(new_shape), new_names}
  end

  def transpose(shape, permutation, _names) do
    raise ArgumentError,
          "expected length of permutation (#{length(permutation)})" <>
            " to match rank of shape (#{tuple_size(shape)})"
  end

  @doc """
  Computes the shape for zip_reduce.

  In order for the dimensions to be correct, the value of each shape
  at the given axes must match. It expects axes to have already been
  normalized.

  ## Examples

      iex> Nx.Shape.zip_reduce({1, 2, 3}, [0, 1], [:batch, :x, :y], {3, 1, 2}, [1, 2], [:batch, :x, :y])
      {{3, 3}, [:y, :batch]}

      iex> Nx.Shape.zip_reduce({1, 2, 3}, [0, 1], [nil, nil, nil], {1, 2, 3}, [1, 2], [nil, nil, nil])
      ** (ArgumentError) dot/zip expects shapes to be compatible, dimension 0 of left-side (1) does not equal dimension 1 of right-side (2)
      
      iex> Nx.Shape.zip_reduce({2, 2}, [1], [:x, :y], {2, 2}, [0], [:y, :x])
      ** (ArgumentError) operation would result in duplicate names [:x, :x], please rename your tensors to avoid duplicates
  """
  def zip_reduce(s1, axes1, names1, s2, axes2, names2) do
    validate_zip_reduce_axes!(s1, axes1, s2, axes2)
    {l1, n1} = Enum.unzip(contract(s1, axes1, names1, 0, tuple_size(s1)))
    {l2, n2} = Enum.unzip(contract(s2, axes2, names2, 0, tuple_size(s2)))
    new_names = n1 ++ n2

    non_nil_names = Enum.filter(new_names, &(&1 != nil))

    if length(non_nil_names) != length(Enum.uniq(non_nil_names)),
      do:
        raise(
          ArgumentError,
          "operation would result in duplicate names #{inspect(new_names)}," <>
            " please rename your tensors to avoid duplicates"
        )

    {List.to_tuple(l1 ++ l2), n1 ++ n2}
  end

  def validate_zip_reduce_axes!(s1, [a1 | axes1], s2, [a2 | axes2]) do
    d1 = elem(s1, a1)
    d2 = elem(s2, a2)

    if d1 == d2 do
      validate_zip_reduce_axes!(s1, axes1, s2, axes2)
    else
      raise ArgumentError,
            "dot/zip expects shapes to be compatible," <>
              " dimension #{a1} of left-side (#{d1}) does not equal" <>
              " dimension #{a2} of right-side (#{d2})"
    end
  end

  def validate_zip_reduce_axes!(_, [], _, []) do
    :ok
  end

  @doc """
  Calculates the padding needed for same padding accounting for stride.

  ## Examples

      iex> Nx.Shape.calculate_padding({4, 4}, {2, 2}, {1, 1})
      [{0, 1}, {0, 1}]

      iex> Nx.Shape.calculate_padding({3, 3}, {2, 2}, {2, 2})
      [{0, 1}, {0, 1}]
  """
  def calculate_padding(shape, window, strides)
      when is_tuple(shape) and is_tuple(window) and is_tuple(strides) do
    validate_window!(shape, window)
    validate_strides!(shape, strides)
    calculate_padding(Tuple.to_list(shape), Tuple.to_list(window), Tuple.to_list(strides))
  end

  def calculate_padding([], [], []), do: []

  def calculate_padding([dim | shape], [w | window], [s | strides]) do
    output_dim = ceil(dim / s)
    padding_size = max((output_dim - 1) * s + w - dim, 0)
    lo = floor(padding_size / 2)
    hi = ceil(padding_size / 2)
    [{lo, hi} | calculate_padding(shape, window, strides)]
  end

  @doc """
  Calculates the padding needed for same padding not accounting for stride.
  """
  def calculate_padding(shape, window) when is_tuple(window) and is_tuple(shape) do
    validate_window!(shape, window)
    calculate_padding(Tuple.to_list(shape), Tuple.to_list(window))
  end

  def calculate_padding([], []), do: []

  def calculate_padding([dim | shape], [w | window]) do
    padding_size = max(dim - 1 + w - dim, 0)
    lo = floor(padding_size / 2)
    hi = ceil(padding_size / 2)
    [{lo, hi} | calculate_padding(shape, window)]
  end

  @doc """
  Output shape after a convolution, already padded.
  """
  def conv(input_shape, input_names, kernel_shape, _kernel_names, strides, padding) do
    filter_shape =
      kernel_shape
      |> Tuple.delete_at(0)
      |> Tuple.delete_at(0)

    num_filters = elem(kernel_shape, 0)
    batch_size = elem(input_shape, 0)

    # Assume padding only pads spatial dims
    padding_config = [{0, 0, 0}, {0, 0, 0} | Enum.map(padding, &Tuple.append(&1, 0))]
    padded_shape = Nx.Shape.pad(input_shape, padding_config)

    old_spatial_dims =
      padded_shape
      |> Tuple.delete_at(0)
      |> Tuple.delete_at(0)
      |> Tuple.to_list()

    spatial_dims =
      do_spatial_dims(old_spatial_dims, Tuple.to_list(filter_shape), Tuple.to_list(strides))

    # TODO: Is it always the case that it's best to return the input names?
    {List.to_tuple([batch_size, num_filters | spatial_dims]), input_names}
  end

  defp do_spatial_dims([], [], []), do: []

  defp do_spatial_dims([cur | spatial], [f | filters], [s | strides]),
    do: [floor((cur - f) / s) + 1 | do_spatial_dims(spatial, filters, strides)]

  @doc """
  Output shape after a window operation.

  ## Examples

      iex> Nx.Shape.window({3, 3}, {2, 2}, {1, 1})
      {2, 2}

      iex> Nx.Shape.window({1, 2, 3}, {2, 1, 1}, {1, 1, 1})
      {1, 2, 3}

  ### Error cases

      iex> Nx.Shape.window({1, 2, 3}, {2, 1}, {1, 1, 1})
      ** (ArgumentError) invalid window dimensions, rank of shape (3) does not match rank of window (2)

      iex> Nx.Shape.window({1, 2, 3}, {2, 1, 1}, {1, 1})
      ** (ArgumentError) invalid stride dimensions, rank of shape (3) does not match rank of stride (2)
  """
  def window(shape, window, strides) do
    validate_window!(shape, window)
    validate_strides!(shape, strides)
    window(Tuple.to_list(shape), Tuple.to_list(window), Tuple.to_list(strides), [])
  end

  defp window([], [], [], acc), do: acc |> Enum.reverse() |> List.to_tuple()

  defp window([dim | shape], [w | window], [s | strides], acc),
    do: window(shape, window, strides, [max(div(dim - w, s) + 1, 1) | acc])

  # Ensures the window is valid given the shape.
  # A window is valid as long as it's rank matches
  # the rank of the given shape.
  defp validate_window!(shape, window)

  defp validate_window!(shape, window) when tuple_size(shape) != tuple_size(window),
    do:
      raise(
        ArgumentError,
        "invalid window dimensions, rank of shape (#{tuple_size(shape)})" <>
          " does not match rank of window (#{tuple_size(window)})"
      )

  defp validate_window!(_, _), do: :ok

  # Ensures the strides are valid given the shape.
  # A stride is valid as long as it's rank matches
  # the rank of the given shape.
  defp validate_strides!(shape, strides)

  defp validate_strides!(shape, strides) when tuple_size(strides) != tuple_size(shape),
    do:
      raise(
        ArgumentError,
        "invalid stride dimensions, rank of shape (#{tuple_size(shape)})" <>
          " does not match rank of stride (#{tuple_size(strides)})"
      )

  defp validate_strides!(_, _), do: :ok

  @doc """
  Output shape after a squeeze operation.

  ## Examples

      iex> Nx.Shape.squeeze({2, 1, 1}, [1, 2], [:batch, :x, :y])
      {{2}, [:batch]}

      iex> Nx.Shape.squeeze({1, 2}, [0], [:batch, :x])
      {{2}, [:x]}

  ### Error cases

      iex> Nx.Shape.squeeze({2, 2, 1}, [1], [:batch, :x, :y])
      ** (ArgumentError) cannot squeeze dimensions whose sizes are not 1, got 2 for dimension 1

  """
  def squeeze(shape, axes, names) do
    squeeze(Enum.with_index(Tuple.to_list(shape)), axes, names, [], [])
  end

  defp squeeze([], _, _, sacc, nacc) do
    {List.to_tuple(Enum.reverse(sacc)), Enum.reverse(nacc)}
  end

  defp squeeze([{s, i} | shape], axes, [n | names], sacc, nacc) do
    if i in axes do
      if s == 1 do
        squeeze(shape, axes, names, sacc, nacc)
      else
        raise ArgumentError,
              "cannot squeeze dimensions whose sizes are not 1, got #{s} for dimension #{i}"
      end
    else
      squeeze(shape, axes, names, [s | sacc], [n | nacc])
    end
  end

  @doc """
  Output shape after a padding operation.

  ## Examples

      iex> Nx.Shape.pad({3, 2, 4}, [{0, 1, 0}, {1, 2, 0}, {1, 1, 0}])
      {4, 5, 6}

      iex> Nx.Shape.pad({}, [])
      {}

      iex> Nx.Shape.pad({2, 2}, [{1, 1, 0}, {0, 0, 0}])
      {4, 2}

      iex> Nx.Shape.pad({2, 3}, [{0, 0, 1}, {0, 0, 1}])
      {3, 5}

  ### Error cases

      iex> Nx.Shape.pad({2, 2, 3}, [{0, 1, 0}, {1, 2, 0}])
      ** (ArgumentError) invalid padding configuration, rank of padding configuration and shape must match
  """
  def pad(shape, padding_config) do
    shape
    |> Tuple.to_list()
    |> padded_dims(padding_config, [])
    |> Enum.reverse()
    |> List.to_tuple()
  end

  defp padded_dims([], [], acc), do: acc

  defp padded_dims([_ | _], [], _acc),
    do:
      raise(
        ArgumentError,
        "invalid padding configuration, rank of padding configuration" <>
          " and shape must match"
      )

  defp padded_dims([], [_ | _], _acc),
    do:
      raise(
        ArgumentError,
        "invalid padding configuration, rank of padding configuration" <>
          " and shape must match"
      )

  defp padded_dims([s | shape], [{edge_low, edge_high, interior} | config], acc) do
    interior_padding_factor = (s - 1) * interior
    padded_dims(shape, config, [s + interior_padding_factor + edge_low + edge_high | acc])
  end

  ## Axes helpers

  @doc """
  Normalize the axis to the given shape.

  ## Examples

      iex> Nx.Shape.normalize_axis({4, 2, 3}, -1, [:batch, :x, :y])
      2

      iex> Nx.Shape.normalize_axis({4, 2, 1, 4}, -2, [:batch, :x, :y, :z])
      2

      iex> Nx.Shape.normalize_axis({4, 2, 1, 4}, 1, [:batch, :x, :y, :z])
      1

      iex> Nx.Shape.normalize_axis({4, 2, 1, 4}, :z, [:batch, :x, :y, :z])
      3

  ### Error cases

      iex> Nx.Shape.normalize_axis({4, 2, 5}, -4, [:batch, :x, :y])
      ** (ArgumentError) given axis (-4) invalid for shape with rank 3

      iex> Nx.Shape.normalize_axis({4, 2, 5}, 3, [:batch, :x, :y])
      ** (ArgumentError) given axis (3) invalid for shape with rank 3

      iex> Nx.Shape.normalize_axis({4, 2, 5}, :z, [:batch, :x, :y])
      ** (ArgumentError) key :z not found in tensor with names [:batch, :x, :y]

      iex> Nx.Shape.normalize_axis({4, 2, 5}, nil, [:batch, nil, nil])
      ** (ArgumentError) axis name cannot be nil

  """
  def normalize_axis(shape, axis, names)

  def normalize_axis(shape, axis, _names) when axis < 0 and abs(axis) <= tuple_size(shape),
    do: tuple_size(shape) + axis

  def normalize_axis(shape, axis, _names) when axis >= 0 and axis < tuple_size(shape),
    do: axis

  def normalize_axis(_shape, nil, _names),
    do: raise(ArgumentError, "axis name cannot be nil")

  def normalize_axis(_shape, axis, names) when is_atom(axis) do
    if axis in names do
      Enum.with_index(names)[axis]
    else
      raise ArgumentError, "key #{inspect(axis)} not found in tensor with names #{inspect(names)}"
    end
  end

  def normalize_axis(shape, axis, _names) do
    raise ArgumentError,
          "given axis (#{inspect(axis)}) invalid for shape with rank #{tuple_size(shape)}"
  end

  @doc """
  Normalize a list of unique axis.

  See `normalize_axis/1`.

  ## Examples

      iex> Nx.Shape.normalize_axes({2, 3, 4}, [-1, 0], [:batch, nil])
      [2, 0]

      iex> Nx.Shape.normalize_axes({2, 3, 4}, [:batch, 1], [:batch, :x])
      [0, 1]

  ### Error Cases

      iex> Nx.Shape.normalize_axes({2, 3, 4}, [1, 1], [nil, nil, nil])
      ** (ArgumentError) axes [1, 1] must be unique integers between 0 and 2
  """
  def normalize_axes(shape, axes, names) when is_list(axes) do
    normalized = Enum.map(axes, &normalize_axis(shape, &1, names))

    if length(Enum.uniq(normalized)) != length(axes) do
      raise ArgumentError,
            "axes #{inspect(axes)} must be unique integers between 0 and #{tuple_size(shape) - 1}"
    end

    normalized
  end

  @doc """
  Returns the axes for transposition.

  ## Examples

      iex> Nx.Shape.transpose_axes({})
      []
      iex> Nx.Shape.transpose_axes({3, 2, 1})
      [2, 1, 0]

  """
  def transpose_axes(shape) do
    rank = tuple_size(shape)
    count_down(rank, rank - 1)
  end

  @doc """
  Compute the broadcast axes based on the shape rank.

  It doesn't validate if the remaining dimensions are
  actually valid.

  ## Examples

      iex> Nx.Shape.broadcast_axes({2, 2, 2}, {2, 2, 2, 2})
      [1, 2, 3]

      iex> Nx.Shape.broadcast_axes({2, 2, 2}, {2, 2, 2, 2, 2})
      [2, 3, 4]

  """
  def broadcast_axes(shape, new_shape) when tuple_size(shape) > tuple_size(new_shape) do
    raise ArgumentError,
          "cannot broadcast tensor of dimensions #{inspect(shape)} " <>
            "to #{inspect(new_shape)}"
  end

  def broadcast_axes(shape, new_shape) do
    min_size = tuple_size(shape)
    max_size = tuple_size(new_shape)
    count_up(min_size, max_size - min_size)
  end

  @doc """
  Returns the axes for squeezing.

  ## Examples

      iex> Nx.Shape.squeeze_axes({2, 1, 1})
      [1, 2]

      iex> Nx.Shape.squeeze_axes({1, 2, 1, 3, 2, 1})
      [0, 2, 5]
  """
  def squeeze_axes(shape) do
    for {1, i} <- Enum.with_index(Tuple.to_list(shape)), do: i
  end

  @doc """
  Returns the shape after a slice.

  ## Examples

      iex> Nx.Shape.slice({2, 15, 30}, [1, 4, 10], [2, 5, 20], [1, 2, 3])
      {1, 1, 4}

  ### Error cases

      iex> Nx.Shape.slice({2, 15, 30}, [1, 4, 10], [0, 5, 11], [1, 2, 3])
      ** (ArgumentError) start and limit indices would result in 0 or negative dimension size, limit indices must be greater than start indices
  """
  def slice(_, start_indices, limit_indices, strides) do
    output_shape =
      limit_indices
      |> Enum.zip(start_indices)
      |> Enum.zip(strides)
      |> Enum.map(fn {{hi, lo}, s} -> Kernel.ceil((hi - lo) / s) end)

    if Enum.any?(output_shape, &(&1 <= 0)) do
      raise ArgumentError,
            "start and limit indices would result in 0 or negative" <>
              " dimension size, limit indices must be greater than" <>
              " start indices"
    end

    List.to_tuple(output_shape)
  end

  ## Helpers

  defp count_up(0, _n), do: []
  defp count_up(i, n), do: [n | count_up(i - 1, n + 1)]

  defp count_down(0, _n), do: []
  defp count_down(i, n), do: [n | count_down(i - 1, n - 1)]

  defp merge_names!(nil, nil), do: nil
  defp merge_names!(nil, name) when is_atom(name), do: name
  defp merge_names!(name, nil) when is_atom(name), do: name
  defp merge_names!(name, name) when is_atom(name), do: name

  defp merge_names!(lhs, rhs),
    do: raise(ArgumentError, "cannot merge names #{inspect(lhs)}, #{inspect(rhs)}")
end
