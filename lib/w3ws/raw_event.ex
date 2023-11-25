defmodule W3WS.RawEvent do
  @moduledoc """
  W3WS RawEvent represents an encoded event.
  """

  @type t :: %__MODULE__{
          address: String.t(),
          block_hash: String.t(),
          block_number: String.t(),
          data: String.t(),
          log_index: String.t(),
          removed: boolean(),
          topics: list(String.t()),
          transaction_hash: String.t(),
          transaction_index: String.t()
        }
  defstruct address: nil,
            block_hash: nil,
            block_number: nil,
            data: nil,
            log_index: nil,
            removed: nil,
            topics: nil,
            transaction_hash: nil,
            transaction_index: nil

  @doc """
  Create a `RawEvent` from a map of log event data
  """
  @spec from_map(map()) :: t()
  def from_map(%{
        "address" => address,
        "blockHash" => block_hash,
        "blockNumber" => block_number,
        "data" => data,
        "logIndex" => log_index,
        "removed" => removed,
        "topics" => topics,
        "transactionHash" => transaction_hash,
        "transactionIndex" => transaction_index
      }) do
    %__MODULE__{
      address: address,
      block_hash: block_hash,
      block_number: block_number,
      data: data,
      log_index: log_index,
      removed: removed,
      topics: topics,
      transaction_hash: transaction_hash,
      transaction_index: transaction_index
    }
  end
end
