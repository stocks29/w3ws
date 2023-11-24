defmodule W3Events.Message do
  @jsonrpc "2.0"

  def eth_block_number(opts \\ []) do
    %{
      jsonrpc: @jsonrpc,
      id: id(opts),
      method: :eth_blockNumber
    }
  end

  def eth_subscribe(params, opts \\ []) do
    %{
      jsonrpc: @jsonrpc,
      id: id(opts),
      method: :eth_subscribe,
      params: params
    }
  end

  def eth_subscribe_logs(topics, opts \\ []) do
    args =
      [topics: topics, address: Keyword.get(opts, :address)]
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Enum.into(%{})

    eth_subscribe([:logs, args], opts)
  end

  def encode!(message), do: Jason.encode!(message)
  def decode!(message), do: Jason.decode!(message)

  defp id(opts), do: Keyword.get(opts, :id, 1)
end
