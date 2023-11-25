defmodule W3WS.Event do
  @moduledoc """
  Event struct representing a decoded event
  """

  @type t :: %__MODULE__{
          address: String.t(),
          block_hash: String.t(),
          block_number: number,
          data: map() | nil,
          fields: list(map()) | nil,
          log_index: number(),
          name: String.t() | nil,
          removed: boolean(),
          topics: list(String.t()),
          transaction_hash: String.t(),
          transaction_index: number()
        }
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

  @spec from_raw_event(raw_event :: W3WS.RawEvent.t()) :: t()
  def from_raw_event(raw_event, selector \\ nil, decoded_data \\ nil)

  @spec from_raw_event(
          raw_event :: W3WS.RawEvent.t(),
          selector :: %ABI.FunctionSelector{} | nil,
          decoded_data :: map() | nil
        ) :: t()
  def from_raw_event(%W3WS.RawEvent{} = raw_event, nil, nil) do
    %__MODULE__{
      address: raw_event.address,
      block_hash: raw_event.block_hash,
      block_number: W3WS.Util.integer_from_hex(raw_event.block_number),
      log_index: W3WS.Util.integer_from_hex(raw_event.log_index),
      removed: raw_event.removed,
      topics: raw_event.topics,
      transaction_hash: raw_event.transaction_hash,
      transaction_index: W3WS.Util.integer_from_hex(raw_event.transaction_index)
    }
  end

  def from_raw_event(
        %W3WS.RawEvent{} = raw_event,
        %ABI.FunctionSelector{} = selector,
        %{} = decoded_data
      ) do
    %{
      from_raw_event(raw_event)
      | data: decoded_data,
        fields: W3WS.ABI.selector_fields(selector),
        name: selector.function
    }
  end
end
