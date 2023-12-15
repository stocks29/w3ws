defmodule W3WS.Handler.TimedRemovalHandlerTest do
  use ExUnit.Case, async: true
  doctest W3WS.Handler.TimedRemovalHandler

  require Logger

  @port 9960

  @abi W3WS.Fixtures.AbiFixtures.abi_fixture()

  alias W3WS.{Listener, Replayer}
  alias W3WS.Handler.TimedRemovalHandler

  defp setup_ws_server(_tags) do
    pid = W3WS.WsServer.start(@port)
    on_exit(fn -> Process.exit(pid, :normal) end)

    {:ok, server: pid, uri: "ws://localhost:#{@port}"}
  end

  defp setup_listener(tags = %{uri: uri}) do
    test_pid = self()

    inner_handler = fn env ->
      Logger.debug("[handler] Received env: #{inspect(env)}")
      send(test_pid, {:env, env})
    end

    handler = {TimedRemovalHandler, handler: inner_handler, delay: 1_000}

    subscription =
      Keyword.merge(
        [handler: handler, abi: @abi],
        tags[:subscription] || []
      )

    config =
      Keyword.merge(
        [uri: uri, subscriptions: [subscription]],
        tags[:config] || []
      )

    {:ok, listener} = Listener.start_link(config)
    on_exit(fn -> Process.exit(listener, :normal) end)

    {:ok, listener: listener}
  end

  defp setup_rpc(%{uri: uri}) do
    {:ok, rpc} = W3WS.Rpc.start_link(uri: uri)
    on_exit(fn -> Process.exit(rpc, :normal) end)

    {:ok, rpc: rpc}
  end

  defp setup_handler(_tags) do
    {:ok, agent} = Agent.start_link(fn -> [] end)
    on_exit(fn -> Process.exit(agent, :normal) end)

    handler = fn env ->
      Agent.update(agent, fn events -> [env | events] end)
    end

    get_events = fn ->
      Agent.get(agent, fn events -> events end)
    end

    handler = {TimedRemovalHandler, handler: handler, delay: 1_000}

    {:ok, handler: handler, get_events: get_events}
  end

  setup_all :setup_ws_server

  describe "with listener" do
    setup :setup_listener

    test "passes non-removed events to inner handler" do
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
                     1500
    end

    test "drops removed events" do
      refute_receive {:env,
                      %W3WS.Env{
                        event: %W3WS.Event{
                          transaction_hash:
                            "0xe776901f5d4049c63f3d464ee60162dd2a1f5c8d949e402e6b9f1d87705b9999",
                          transaction_index: 0
                        },
                        jsonrpc: "2.0",
                        method: "eth_subscription",
                        raw: %W3WS.RawEvent{
                          transaction_hash:
                            "0xe776901f5d4049c63f3d464ee60162dd2a1f5c8d949e402e6b9f1d87705b9999",
                          transaction_index: "0x0"
                        },
                        subscription: "0x9"
                      }},
                     1500
    end
  end

  describe "with replayer" do
    setup :setup_rpc
    setup :setup_handler

    test "drops removed events", %{uri: uri, handler: handler, get_events: get_events} do
      Replayer.replay(
        uri: uri,
        from_block: 1,
        chunk_size: 5,
        chunk_sleep: 0,
        replays: [
          [handler: handler]
        ]
      )

      # wait for delayed events to be sent
      :timer.sleep(1500)

      events = get_events.()
      assert length(events) == 2
      refute Enum.any?(events, fn env -> env.event.removed end)

      refute Enum.any?(events, fn env ->
               env.event.transaction_hash ==
                 "0xe776901f5d4049c63f3d464ee60162dd2a1f5c8d949e402e6b9f1d87705b9999"
             end)
    end
  end
end
