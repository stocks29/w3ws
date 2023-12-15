defmodule W3WS.Message do
  @moduledoc """
  W3WS Messages for ethereum jsonrpc

  See [Ethereum JSON-RPC docs](https://ethereum.org/en/developers/docs/apis/json-rpc/)
  for more information.

  This is not meant to be an exhaustive list of all possible messages. Users are
  encouraged to use their own messages when necessary.
  """

  @jsonrpc "2.0"

  @doc """
  Create an `eth_blockNumber` request
  """
  def eth_block_number(opts \\ []) do
    %{
      jsonrpc: @jsonrpc,
      id: id(opts),
      method: :eth_blockNumber
    }
  end

  @doc """
  Create an `eth_getLogs` request.

  Takes a `params` argument which will be used as the `params` field in the message.
  """
  def eth_get_logs(opts \\ []) do
    filter =
      %{
        address: Keyword.get(opts, :address),
        topics: Keyword.get(opts, :topics),
        fromBlock: Keyword.get(opts, :from_block),
        toBlock: Keyword.get(opts, :to_block),
        blockHash: Keyword.get(opts, :block_hash)
      }
      |> strip_nil_values()

    # TODO: should we not include id in event if it wasn't
    # explicitly specified?
    %{
      jsonrpc: @jsonrpc,
      id: id(opts),
      method: :eth_getLogs,
      params: [filter]
    }
  end

  @doc """
  Create an `eth_subscribe` request

  Takes a `params` argument which will be used as the `params` field in the message.
  """
  def eth_subscribe(params, opts \\ []) do
    %{
      jsonrpc: @jsonrpc,
      id: id(opts),
      method: :eth_subscribe,
      params: params
    }
  end

  @doc """
  Create an `eth_subscribe` request for "logs".

  This is a convenience function and not part of the JSON-RPC spec.
  """
  def eth_subscribe_logs(topics, opts \\ []) do
    args =
      [topics: topics, address: Keyword.get(opts, :address)]
      |> strip_nil_values()

    eth_subscribe([:logs, args], opts)
  end

  @doc """
  Create an `eth_subscribe` request for "newHeads".

  This is a convenience function and not part of the JSON-RPC spec.
  """
  def eth_subscribe_new_heads(opts \\ []) do
    eth_subscribe([:newHeads], opts)
  end

  @doc """
  Create an `eth_unsubscribe` request.

  Takes a `subscription` argument which will be used as the subscription 
  identifier in the request.
  """
  def eth_unsubscribe(subscription, opts \\ []) do
    %{
      jsonrpc: @jsonrpc,
      id: id(opts),
      method: :eth_unsubscribe,
      params: [subscription]
    }
  end

  @doc """
  Encode the message as json
  """
  def encode!(message), do: Jason.encode!(message)

  @doc """
  Dencode the message from json
  """
  def decode!(message), do: Jason.decode!(message)

  defp id(opts), do: Keyword.get(opts, :id, 1)

  @doc """
  Set the message id
  """
  def set_id(message, id), do: Map.put(message, :id, id)

  defp strip_nil_values(map) do
    map
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Enum.into(%{})
  end
end
