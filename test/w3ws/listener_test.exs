defmodule W3WS.ListenerTest do
  use ExUnit.Case, async: true
  doctest W3WS.Listener

  require Logger

  @port 9955

  @abi [
    %{
      "name" => "TokenSupportChange",
      "type" => "event",
      "inputs" => [
        %{
          "name" => "supported",
          "indexed" => false,
          "internalType" => "bool",
          "type" => "bool"
        },
        %{
          "name" => "token",
          "indexed" => false,
          "internalType" => "address",
          "type" => "address"
        },
        %{
          "name" => "symbol",
          "indexed" => false,
          "internalType" => "string",
          "type" => "string"
        },
        %{
          "name" => "decimals",
          "indexed" => false,
          "internalType" => "uint8",
          "type" => "uint8"
        }
      ]
    }
  ]

  alias W3WS.Listener

  defp setup_ws_server(_tags) do
    pid = W3WS.WsServer.start(@port)
    on_exit(fn -> Process.exit(pid, :normal) end)

    {:ok, server: pid, uri: "ws://localhost:#{@port}"}
  end

  defp setup_listener(tags = %{uri: uri}) do
    test_pid = self()

    handler = fn env ->
      Logger.debug("[handler] Received env: #{inspect(env)}")
      send(test_pid, {:env, env})
    end

    subscription =
      Map.merge(
        %{
          handler: handler,
          abi: @abi
        },
        tags[:subscription] || %{}
      )

    config =
      Map.merge(
        %{
          uri: uri,
          subscriptions: [subscription]
        },
        tags[:config] || %{}
      )

    {:ok, listener} = Listener.start_link(config)
    on_exit(fn -> Process.exit(listener, :normal) end)

    {:ok, listener: listener}
  end

  setup_all :setup_ws_server
  setup :setup_listener

  test "listens for and decodes events" do
    assert_receive {:env,
                    %W3WS.Env{
                      context: %{},
                      decoded?: true,
                      event: %W3WS.Event{
                        address: "0x73d578371eb449726d727376393b02bb3b8e6a57",
                        block_hash:
                          "0x6f917eb430805db84a84d4e71633d8dfc80f864cf06cc53bc65c6ea0fa0eab5d",
                        block_number: 1,
                        data: %{
                          "decimals" => 18,
                          "supported" => true,
                          "symbol" => "ARB",
                          "token" => "0x959922be3caee4b8cd9a407cc3ac1c251c2007b1"
                        },
                        fields: [
                          %{name: "supported", type: :bool, indexed: false},
                          %{name: "token", type: :address, indexed: false},
                          %{name: "symbol", type: :string, indexed: false},
                          %{name: "decimals", type: {:uint, 8}, indexed: false}
                        ],
                        log_index: 0,
                        name: "TokenSupportChange",
                        removed: false,
                        topics: [
                          "0x0148cba56e5d3a8d32fbcea206eae9e449ec0f0def4f642994b3edcd38561deb"
                        ],
                        transaction_hash:
                          "0xe776901f5d4049c63f3d464ee60162dd2a1f5c8d949e402e6b9f1d87705b2861",
                        transaction_index: 0
                      },
                      jsonrpc: "2.0",
                      method: "eth_subscription",
                      raw: %W3WS.RawEvent{
                        address: "0x73d578371eb449726d727376393b02bb3b8e6a57",
                        block_hash:
                          "0x6f917eb430805db84a84d4e71633d8dfc80f864cf06cc53bc65c6ea0fa0eab5d",
                        block_number: "0x1",
                        data:
                          "0x0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000959922be3caee4b8cd9a407cc3ac1c251c2007b10000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000034152420000000000000000000000000000000000000000000000000000000000",
                        log_index: "0x0",
                        removed: false,
                        topics: [
                          "0x0148cba56e5d3a8d32fbcea206eae9e449ec0f0def4f642994b3edcd38561deb"
                        ],
                        transaction_hash:
                          "0xe776901f5d4049c63f3d464ee60162dd2a1f5c8d949e402e6b9f1d87705b2861",
                        transaction_index: "0x0"
                      },
                      subscription: "0x9"
                    }},
                   500
  end

  @tag subscription: %{context: %{chain_id: 1}}
  test "includes contents in env" do
    assert_receive {:env, %W3WS.Env{context: %{chain_id: 1}}}, 500
  end

  @tag config: %{resubscribe: 100}
  test "resubscribes on given interval" do
    assert_receive {:env, %W3WS.Env{}}, 1000
    assert_receive {:env, %W3WS.Env{}}, 1000
    assert_receive {:env, %W3WS.Env{}}, 1000
  end

  @tag subscription: %{abi: nil}
  test "returns encoded event when no abi to decode" do
    assert_receive {:env,
                    %W3WS.Env{
                      decoded?: false,
                      event: %W3WS.Event{
                        address: "0x73d578371eb449726d727376393b02bb3b8e6a57",
                        block_number: 1,
                        data: nil
                      }
                    }},
                   500
  end

  @tag config: %{block_ping: 50}
  test "pings for current block when configured", %{listener: listener} do
    :timer.sleep(500)
    assert Listener.get_block(listener) == 7
  end

  test "does not ping for current block when not configured", %{listener: listener} do
    :timer.sleep(500)
    assert Listener.get_block(listener) == nil
  end
end
