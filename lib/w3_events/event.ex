defmodule W3Events.Event do
  defstruct address: nil,
            block_hash: nil,
            block_number: nil,
            data: nil,
            fields: nil,
            log_index: nil,
            name: nil,
            removed: nil,
            topics: nil,
            transaction_hash: nil,
            transaction_index: nil

  def from_raw_event(
        %W3Events.RawEvent{} = raw_event,
        %ABI.FunctionSelector{} = selector,
        %{} = decoded_data
      ) do
    %__MODULE__{
      address: raw_event.address,
      block_hash: raw_event.block_hash,
      block_number: W3Events.Util.integer_from_hex(raw_event.block_number),
      data: decoded_data,
      log_index: W3Events.Util.integer_from_hex(raw_event.log_index),
      name: selector.function,
      fields: W3Events.ABI.selector_fields(selector),
      removed: raw_event.removed,
      topics: raw_event.topics,
      transaction_hash: raw_event.transaction_hash,
      transaction_index: W3Events.Util.integer_from_hex(raw_event.transaction_index)
    }
  end
end
