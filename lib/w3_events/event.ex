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

  def from_raw_event(raw_event, selector \\ nil, decoded_data \\ nil)

  def from_raw_event(%W3Events.RawEvent{} = raw_event, nil, nil) do
    %__MODULE__{
      address: raw_event.address,
      block_hash: raw_event.block_hash,
      block_number: W3Events.Util.integer_from_hex(raw_event.block_number),
      log_index: W3Events.Util.integer_from_hex(raw_event.log_index),
      removed: raw_event.removed,
      topics: raw_event.topics,
      transaction_hash: raw_event.transaction_hash,
      transaction_index: W3Events.Util.integer_from_hex(raw_event.transaction_index)
    }
  end

  def from_raw_event(
        %W3Events.RawEvent{} = raw_event,
        %ABI.FunctionSelector{} = selector,
        %{} = decoded_data
      ) do
    %{
      from_raw_event(raw_event)
      | data: decoded_data,
        fields: W3Events.ABI.selector_fields(selector),
        name: selector.function
    }
  end
end
