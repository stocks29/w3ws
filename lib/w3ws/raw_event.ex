defmodule W3WS.RawEvent do
  defstruct address: nil,
            block_hash: nil,
            block_number: nil,
            data: nil,
            log_index: nil,
            removed: nil,
            topics: nil,
            transaction_hash: nil,
            transaction_index: nil

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
