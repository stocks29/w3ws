defmodule W3WS.Env do
  defstruct event: nil,
            context: %{},
            decoded?: false,
            jsonrpc: nil,
            method: nil,
            raw: nil,
            subscription: nil

  @doc """
  Create an envelope from an eth_subscription response

    ## Examples
    
    iex> from_eth_subscription(
    ...>   %{
    ...>     "jsonrpc" => "2.0", 
    ...>     "method" => "eth_subscription", 
    ...>     "params" => %{
    ...>       "subscription" => "0x9", 
    ...>       "result" => %{
    ...>         "address" => "0xAddress",
    ...>         "blockHash" => "0xBlockHash",
    ...>         "blockNumber" => "0x1",
    ...>         "data" => "0xData",
    ...>         "logIndex" => "0x0",
    ...>         "removed" => false,
    ...>         "topics" => ["0xTopic"],
    ...>         "transactionHash" => "0xTransactionHash",
    ...>         "transactionIndex" => "0x2"
    ...>       }
    ...>     }
    ...>   },
    ...>   %{chain_id: 1}
    ...> )
    %W3WS.Env{
      context: %{chain_id: 1},
      decoded?: false,
      event: nil,
      jsonrpc: "2.0",
      method: "eth_subscription",
      raw: %W3WS.RawEvent{
        address: "0xAddress",
        block_hash: "0xBlockHash",
        block_number: "0x1",
        data: "0xData",
        log_index: "0x0",
        removed: false,
        topics: ["0xTopic"],
        transaction_hash: "0xTransactionHash",
        transaction_index: "0x2"
      },
      subscription: "0x9"
    }

  """
  def from_eth_subscription(
        %{
          "jsonrpc" => jsonrpc,
          "method" => method,
          "params" => %{
            "result" => result,
            "subscription" => subscription
          }
        },
        context
      ) do
    %__MODULE__{
      context: context,
      jsonrpc: jsonrpc,
      method: method,
      raw: W3WS.RawEvent.from_map(result),
      subscription: subscription
    }
  end

  def with_event(%__MODULE__{} = env, %W3WS.Event{} = event) do
    %{env | decoded?: event.data != nil, event: event}
  end
end