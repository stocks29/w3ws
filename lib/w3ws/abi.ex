defmodule W3WS.ABI do
  @moduledoc """
  Ethereum ABI Functions
  """

  @type t :: list(%ABI.FunctionSelector{})

  @doc """
  Loads ABIs from an `Enumerable` of abi file paths

  ## Examples

      iex> [%ABI.FunctionSelector{
      ...>   type: :event,
      ...>   function: "Transfer",
      ...>   input_names: ["from", "to", "value"],
      ...>   inputs_indexed: [false, false, false],
      ...>   types: [:address, :address, {:uint, 256}]
      ...> }] = from_files(["./test/support/files/test_abi.json"])
  """
  def from_files(paths) do
    Enum.flat_map(paths, fn path ->
      path
      |> File.read!()
      |> W3WS.json_module().decode!()
      |> ABI.parse_specification(include_events?: true)
      |> filter_abi_events()
    end)
  end

  @doc """
  Loads an ABI from a json decoded ABI spec

  ## Examples

      iex> [%ABI.FunctionSelector{
      ...>   type: :event,
      ...>   function: "Transfer",
      ...>   input_names: ["from", "to", "value"],
      ...>   inputs_indexed: [false, false, false],
      ...>   types: [:address, :address, {:uint, 256}]
      ...> }] = from_abi([
      ...>   %{
      ...>     "name" => "Transfer",
      ...>     "type" => "event",
      ...>     "inputs" => [
      ...>       %{
      ...>         "name" => "from",
      ...>         "type" => "address",
      ...>         "indexed" => false,
      ...>         "internalType" => "address"
      ...>       },
      ...>       %{
      ...>         "name" => "to",
      ...>         "type" => "address",
      ...>         "indexed" => false,
      ...>         "internalType" => "address"
      ...>       },
      ...>       %{
      ...>         "name" => "value",
      ...>         "type" => "uint256",
      ...>         "indexed" => false,
      ...>         "internalType" => "uint256"
      ...>       }
      ...>     ]
      ...>   }
      ...> ])
  """
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

      iex> abi = from_abi([
      ...>   %{
      ...>     "name" => "TokenSupportChange",
      ...>     "type" => "event",
      ...>     "inputs" => [
      ...>       %{"name" => "supported", "type" => "bool", "indexed" => false},
      ...>       %{"name" => "token", "type" => "address", "indexed" => false},
      ...>       %{"name" => "symbol", "type" => "string", "indexed" => false},
      ...>       %{"name" => "decimals", "type" => "uint8", "indexed" => false}
      ...>     ]
      ...>   }
      ...> ])
      iex> {:ok, %ABI.FunctionSelector{function: "TokenSupportChange"}, decoded} = decode_event(
      ...>   "0x0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000959922be3caee4b8cd9a407cc3ac1c251c2007b10000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000034152420000000000000000000000000000000000000000000000000000000000",
      ...>   abi,
      ...>   ["0x0148cba56e5d3a8d32fbcea206eae9e449ec0f0def4f642994b3edcd38561deb"]
      ...> )
      iex> decoded
      %{
        "decimals" => 18,
        "supported" => true,
        "symbol" => "ARB",
        "token" => "0x959922be3caee4b8cd9a407cc3ac1c251c2007b1"
      }
  """
  @spec decode_event(binary(), list(%ABI.FunctionSelector{}), [binary()]) ::
          {:ok, %ABI.FunctionSelector{}, map()} | {:error, any()}
  def decode_event(data, abi, topics) do
    topics =
      Enum.map(topics, fn
        nil -> nil
        topic -> W3WS.Util.from_hex(topic)
      end)

    case ABI.Event.find_and_decode(
           abi,
           Enum.at(topics, 0),
           Enum.at(topics, 1),
           Enum.at(topics, 2),
           Enum.at(topics, 3),
           W3WS.Util.from_hex(data)
         ) do
      {:error, _} = err -> err
      {selector, event_data} -> {:ok, selector, decode_data(event_data)}
    end
  end

  @doc """
  Encodes a list of topics into their keccak hex representation

  ## Examples

      iex> encode_topics([
      ...>   "0x0000000000000000000000000000000000000000000000000000000000000001", 
      ...>   "0x0000000000000000000000000000000000000000000000000000000000000002",
      ...>   "SomeEvent",
      ...>   ["SomeEvent(uint8,uint8)"],
      ...>   "MissingAbiEvent(uint8)",
      ...>  nil
      ...> ], [
      ...>   %ABI.FunctionSelector{
      ...>     function: "SomeEvent",
      ...>     method_id: <<1, 72, 203, 165>>,
      ...>     type: :event,
      ...>     inputs_indexed: [false, false],
      ...>     state_mutability: nil,
      ...>     input_names: ["a", "b"],
      ...>     types: [{:uint, 8}, {:uint, 8}],
      ...>     returns: [],
      ...>     return_names: []
      ...>   } 
      ...> ])
      [
        "0x0000000000000000000000000000000000000000000000000000000000000001", 
        "0x0000000000000000000000000000000000000000000000000000000000000002", 
        "0xf4907308003e0ac1411f27720554a08b629260c5bcd94e153d38a3ad5d4ce8ad", 
        ["0xf4907308003e0ac1411f27720554a08b629260c5bcd94e153d38a3ad5d4ce8ad"], 
        "0x961ac6e850917325cc201160e6c6a650f0be9ec0fcae82c74d760ab6a9c0e7b0", 
        nil
      ]
  """
  def encode_topics(topics, abi) do
    Enum.map(topics, &encode_topic(&1, abi))
  end

  defp encode_topic(nil = topic, _abi), do: topic

  defp encode_topic("0x" <> _rest = topic, _abi), do: topic

  defp encode_topic(topic, nil) when is_binary(topic) do
    raise "Unable to encode topic #{inspect(topic)} as no ABI was provided"
  end

  defp encode_topic(topic, abi) when is_binary(topic) do
    {selector_name, backup_selector} =
      if String.contains?(topic, "(") do
        # this is an event signature, so convert it to a FunctionSelector
        selector = %ABI.FunctionSelector{function: name} = ABI.FunctionSelector.decode(topic)
        {name, selector}
      else
        # must be an event name
        {topic, nil}
      end

    # find the authoritative selector in the ABI so find the selector
    selector =
      Enum.find(abi, fn
        %ABI.FunctionSelector{type: :event, function: name} -> selector_name == name
        _ -> false
      end)

    selector = if is_nil(selector), do: backup_selector, else: selector

    selector
    |> selector_signature()
    |> W3WS.Util.keccak(hex?: true)
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

  defp decode_value({_name, "address", _indexed, value}), do: W3WS.Util.to_hex(value)
  defp decode_value({_name, _type, true, {:dynamic, value}}), do: W3WS.Util.to_hex(value)
  defp decode_value({_name, _type, _indexed, value}), do: value

  @doc """
  Returns a list of ABI fields for the given selector

  ## Examples

      iex> selector_fields(%ABI.FunctionSelector{
      ...>   function: "SomeEvent", 
      ...>   method_id: <<1, 72, 203, 165>>,
      ...>   type: :event,
      ...>   inputs_indexed: [false, false],
      ...>   input_names: ["a", "b"],
      ...>   types: [{:uint, 8}, {:uint, 8}],
      ...>   returns: [],
      ...>   return_names: []
      ...> })
      [
        %{name: "a", indexed: false, type: {:uint, 8}},
        %{name: "b", indexed: false, type: {:uint, 8}}
      ]
  """
  @spec selector_fields(selector :: %ABI.FunctionSelector{}) :: list(map())
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
