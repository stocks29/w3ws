defmodule W3WS.RpcTest do
  use ExUnit.Case, async: true
  doctest W3WS.Rpc

  require Logger
  alias W3WS.Rpc
  import W3WS.Message

  @port 9957

  defp setup_ws_server(_tags) do
    pid = W3WS.WsServer.start(@port)
    on_exit(fn -> Process.exit(pid, :normal) end)

    {:ok, server: pid, uri: "ws://localhost:#{@port}"}
  end

  defp setup_rpc(%{uri: uri}) do
    {:ok, rpc} = Rpc.start_link(uri: uri)
    on_exit(fn -> Process.exit(rpc, :normal) end)

    {:ok, rpc: rpc}
  end

  setup_all :setup_ws_server
  setup :setup_rpc

  test "returns logs when requested", %{rpc: rpc} do
    {:ok,
     %{
       "id" => 1,
       "jsonrpc" => "2.0",
       "result" => [
         %{
           "address" => "0x73d578371eb449726d727376393b02bb3b8e6a57",
           "blockHash" => "0x6f917eb430805db84a84d4e71633d8dfc80f864cf06cc53bc65c6ea0fa0eab5d",
           "blockNumber" => "0x1",
           "data" =>
             "0x0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000959922be3caee4b8cd9a407cc3ac1c251c2007b10000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000034152420000000000000000000000000000000000000000000000000000000000",
           "logIndex" => "0x0",
           "removed" => false,
           "topics" => ["0x0148cba56e5d3a8d32fbcea206eae9e449ec0f0def4f642994b3edcd38561deb"],
           "transactionHash" =>
             "0xe776901f5d4049c63f3d464ee60162dd2a1f5c8d949e402e6b9f1d87705b2861",
           "transactionIndex" => "0x0"
         }
       ]
     }} = Rpc.send_message(rpc, eth_get_logs([]))
  end

  test "returns current block when requested", %{rpc: rpc} do
    assert {:ok,
            %{"id" => 1, "jsonrpc" => "2.0", "method" => "eth_blockNumber", "result" => "0x7"}} ==
             Rpc.send_message(rpc, eth_block_number())
  end

  test "can support multiple concurrent calls", %{rpc: rpc} do
    task1 = Task.async(fn -> Rpc.send_message(rpc, eth_block_number()) end)
    task2 = Task.async(fn -> Rpc.send_message(rpc, eth_get_logs([])) end)
    task3 = Task.async(fn -> Rpc.send_message(rpc, eth_block_number()) end)

    [result1, result2, result3] = Task.await_many([task1, task2, task3])

    assert {:ok,
            %{"id" => id1, "jsonrpc" => "2.0", "method" => "eth_blockNumber", "result" => "0x7"}} =
             result1

    assert {:ok,
            %{
              "id" => id2,
              "jsonrpc" => "2.0",
              "result" => [
                %{
                  "address" => "0x73d578371eb449726d727376393b02bb3b8e6a57",
                  "blockHash" =>
                    "0x6f917eb430805db84a84d4e71633d8dfc80f864cf06cc53bc65c6ea0fa0eab5d",
                  "blockNumber" => "0x1",
                  "data" =>
                    "0x0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000959922be3caee4b8cd9a407cc3ac1c251c2007b10000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000034152420000000000000000000000000000000000000000000000000000000000",
                  "logIndex" => "0x0",
                  "removed" => false,
                  "topics" => [
                    "0x0148cba56e5d3a8d32fbcea206eae9e449ec0f0def4f642994b3edcd38561deb"
                  ],
                  "transactionHash" =>
                    "0xe776901f5d4049c63f3d464ee60162dd2a1f5c8d949e402e6b9f1d87705b2861",
                  "transactionIndex" => "0x0"
                }
              ]
            }} = result2

    assert {:ok,
            %{"id" => id3, "jsonrpc" => "2.0", "method" => "eth_blockNumber", "result" => "0x7"}} =
             result3

    assert id1 != id2
    assert id2 != id3
    assert id3 != id1
  end

  test "can subscribe to events", %{rpc: rpc} do
    {:ok, %{"result" => "0x9"}} = Rpc.send_message(rpc, eth_subscribe_logs([]))
    assert_receive {:eth_subscription, %{"params" => %{"subscription" => "0x9"}}}
  end

  test "gracefully handles a subscribed process that exits", %{rpc: rpc} do
    task = Task.async(fn -> Rpc.send_message(rpc, eth_subscribe_logs([])) end)
    assert {:ok, _resp} = Task.await(task)

    # can still make calls
    assert {:ok, %{"result" => "0x7"}} = Rpc.send_message(rpc, eth_block_number())
  end

  test "can send async messages", %{rpc: rpc} do
    ref1 = Rpc.async_message(rpc, eth_block_number())
    ref2 = Rpc.async_message(rpc, eth_block_number())

    assert_receive {:eth_response, ^ref1,
                    %{
                      "id" => 1,
                      "jsonrpc" => "2.0",
                      "method" => "eth_blockNumber",
                      "result" => "0x7"
                    }, _req},
                   200

    assert_receive {:eth_response, ^ref2,
                    %{
                      "id" => 2,
                      "jsonrpc" => "2.0",
                      "method" => "eth_blockNumber",
                      "result" => "0x7"
                    }, _req},
                   200
  end

  test "can mix async and sync calls", %{rpc: rpc} do
    ref1 = Rpc.async_message(rpc, eth_block_number())
    {:ok, _res} = Rpc.send_message(rpc, eth_block_number())
    ref2 = Rpc.async_message(rpc, eth_block_number())
    {:ok, _res} = Rpc.send_message(rpc, eth_block_number())

    assert_receive {:eth_response, ^ref1,
                    %{
                      "id" => 1,
                      "jsonrpc" => "2.0",
                      "method" => "eth_blockNumber",
                      "result" => "0x7"
                    }, _req},
                   200

    assert_receive {:eth_response, ^ref2,
                    %{
                      "id" => 3,
                      "jsonrpc" => "2.0",
                      "method" => "eth_blockNumber",
                      "result" => "0x7"
                    }, _req},
                   200
  end
end
