defmodule W3Events.ABI do
  def from_files(paths) do
    Enum.flat_map(paths, fn path ->
      path
      |> File.read!()
      |> Jason.decode!()
      |> ABI.parse_specification(include_events?: true)
      |> filter_abi_events()
    end)
  end

  def from_abi(abi) do
    abi
    |> ABI.parse_specification(include_events?: true)
    |> filter_abi_events()
  end

  defp filter_abi_events(abi) do
    Enum.filter(abi, fn %ABI.FunctionSelector{type: type} -> type == :event end)
  end

  @doc """
  Decodes an event from a raw event

  ## Examples

    iex> decode_event(
    ...>   "0x0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000959922be3caee4b8cd9a407cc3ac1c251c2007b10000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000034152420000000000000000000000000000000000000000000000000000000000",
    ...>   [
    ...>      %ABI.FunctionSelector{
    ...>        function: "TokenSupportChange",
    ...>        method_id: <<1, 72, 203, 165>>,
    ...>        type: :event,
    ...>        inputs_indexed: [false, false, false, false],
    ...>        state_mutability: nil,
    ...>        input_names: ["supported", "token", "symbol", "decimals"],
    ...>        types: [:bool, :address, :string, {:uint, 8}],
    ...>        returns: [],
    ...>        return_names: []
    ...>      }
    ...>   ],
    ...>   ["0x0148cba56e5d3a8d32fbcea206eae9e449ec0f0def4f642994b3edcd38561deb"]
    ...> )
    {
      :ok, 
      %ABI.FunctionSelector{
        function: "TokenSupportChange",
        method_id: <<1, 72, 203, 165>>,
        type: :event,
        inputs_indexed: [false, false, false, false],
        state_mutability: nil,
        input_names: ["supported", "token", "symbol", "decimals"],
        types: [:bool, :address, :string, {:uint, 8}],
        returns: [],
        return_names: []
      }, 
      %{"decimals" => 18, "supported" => true, "symbol" => "ARB", "token" => "0x959922be3caee4b8cd9a407cc3ac1c251c2007b1"}
    }
  """
  @spec decode_event(binary(), ABI.specification(), [binary()]) ::
          {:ok, ABI.selector(), map()} | {:error, any()}
  def decode_event(data, abi, topics) do
    topics =
      Enum.map(topics, fn
        nil -> nil
        topic -> W3Events.Util.from_hex(topic)
      end)

    case ABI.Event.find_and_decode(
           abi,
           Enum.at(topics, 0),
           Enum.at(topics, 1),
           Enum.at(topics, 2),
           Enum.at(topics, 3),
           W3Events.Util.from_hex(data)
         ) do
      {:error, _} = err -> err
      {selector, event_data} -> {:ok, selector, decode_data(event_data)}
    end
  end

  def encode_topics(topics, abi) do
    Enum.map(topics, &encode_topic(&1, abi))
  end

  defp encode_topic(nil = topic, _abi), do: topic

  defp encode_topic("0x" <> _rest = topic, _abi), do: topic

  defp encode_topic(topic, nil) when is_binary(topic) do
    raise "Unable to encode topic #{inspect(topic)} as no ABI was provided"
  end

  defp encode_topic(topic, abi) when is_binary(topic) do
    selector =
      if String.contains?(topic, "(") do
        # this is an event signature, so convert it to a FunctionSelector
        topic
        |> ABI.FunctionSelector.decode()
      else
        # must be an event name, so find the selector
        Enum.find(abi, fn
          %ABI.FunctionSelector{type: :event, function: name} -> topic == name
          _ -> false
        end)
      end

    selector
    |> selector_signature()
    |> W3Events.Util.keccak(hex?: true)
  end

  defp encode_topic(sub_topics, abi) when is_list(sub_topics) do
    Enum.map(sub_topics, &encode_topic(&1, abi))
  end

  defp selector_signature(selector) do
    non_indexed_types =
      selector
      |> selector_fields()
      |> Enum.reject(& &1[:indexed])
      |> Enum.map(&Map.get(&1, :type))
      |> Enum.map(&ABI.FunctionSelector.encode_type/1)

    Enum.join([selector.function, "(", Enum.join(non_indexed_types, ","), ")"])
  end

  defp decode_data(event_data) do
    Enum.reduce(event_data, %{}, fn field = {name, _type, _indexed, _value}, acc ->
      Map.put(acc, name, decode_value(field))
    end)
  end

  defp decode_value({_name, "address", _indexed, value}), do: W3Events.Util.to_hex(value)
  defp decode_value({_name, _type, true, {:dynamic, value}}), do: W3Events.Util.to_hex(value)
  defp decode_value({_name, _type, _indexed, value}), do: value

  def selector_fields(selector = %ABI.FunctionSelector{inputs_indexed: nil, types: types}) do
    stream = Stream.repeatedly(fn -> false end)

    %{selector | inputs_indexed: Enum.take(stream, length(types))}
    |> selector_fields()
  end

  def selector_fields(selector = %ABI.FunctionSelector{input_names: [], types: types}) do
    stream = Stream.repeatedly(fn -> "" end)

    %{selector | input_names: Enum.take(stream, length(types))}
    |> selector_fields()
  end

  def selector_fields(%ABI.FunctionSelector{
        input_names: input_names,
        inputs_indexed: inputs_indexed,
        types: types
      }) do
    [input_names, inputs_indexed, types]
    |> Enum.zip()
    |> Enum.map(fn {name, indexed, type} -> %{name: name, indexed: indexed, type: type} end)
  end
end
