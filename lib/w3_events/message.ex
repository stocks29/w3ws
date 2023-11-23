defmodule W3Events.Message do

  def eth_subscribe(params, opts \\ []) do
    %{
      jsonrpc: "2.0",
      id: Keyword.get(opts, :id, 1),
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
end
