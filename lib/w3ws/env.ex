defmodule W3WS.Env do
  defstruct event: nil,
            decoded?: false,
            jsonrpc: nil,
            method: nil,
            raw: nil,
            subscription: nil

  def from_eth_subscription(%{
        "jsonrpc" => jsonrpc,
        "method" => method,
        "params" => %{
          "result" => result,
          "subscription" => subscription
        }
      }) do
    %__MODULE__{
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
