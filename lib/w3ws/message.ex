defmodule W3WS.Message do
  @moduledoc """
  W3WS Messages for ethereum jsonrpc
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
  Create an `eth_subscribe` request
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
  Create an `eth_subscribe` request for "logs"
  """
  def eth_subscribe_logs(topics, opts \\ []) do
    args =
      [topics: topics, address: Keyword.get(opts, :address)]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.into(%{})

    eth_subscribe([:logs, args], opts)
  end

  @doc """
  Create an `eth_unsubscribe` request
  """
  def eth_unsubscribe(sub_id, opts \\ []) do
    %{
      jsonrpc: @jsonrpc,
      id: id(opts),
      method: :eth_unsubscribe,
      params: [sub_id]
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
end
