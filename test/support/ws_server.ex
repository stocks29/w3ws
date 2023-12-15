defmodule W3WS.WsServer do
  require Logger

  defp client_handler(client) do
    case Socket.Web.recv!(client) do
      {:close, _, _} ->
        # client closed connection
        :ok

      {:text, data} ->
        data = Jason.decode!(data)
        Logger.debug("[server] received data: #{inspect(data)}")

        case data do
          %{"method" => "eth_blockNumber"} ->
            Logger.debug("[server] sending eth_blockNumber response")

            Socket.Web.send!(
              client,
              {
                :text,
                Jason.encode!(%{
                  "id" => data["id"],
                  "jsonrpc" => "2.0",
                  "method" => "eth_blockNumber",
                  "result" => "0x7"
                })
              }
            )

          %{"method" => "eth_unsubscribe"} ->
            Logger.debug("[server] sending eth_unsubscribe response")

            Socket.Web.send!(
              client,
              {
                :text,
                Jason.encode!(%{
                  "id" => data["id"],
                  "jsonrpc" => "2.0",
                  "method" => "eth_unsubscribe",
                  "result" => true
                })
              }
            )

          %{"method" => "eth_getLogs"} ->
            Logger.debug("[server] sending eth_get_logs response")

            Socket.Web.send!(
              client,
              {:text,
               Jason.encode!(%{
                 "id" => data["id"],
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
                   },
                   # event which will be removed
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
                       "0xe776901f5d4049c63f3d464ee60162dd2a1f5c8d949e402e6b9f1d87705b9999",
                     "transactionIndex" => "0x0"
                   },
                   # remove the second event
                   %{
                     "address" => "0x73d578371eb449726d727376393b02bb3b8e6a57",
                     "blockHash" =>
                       "0x6f917eb430805db84a84d4e71633d8dfc80f864cf06cc53bc65c6ea0fa0eab5d",
                     "blockNumber" => "0x1",
                     "data" =>
                       "0x0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000959922be3caee4b8cd9a407cc3ac1c251c2007b10000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000034152420000000000000000000000000000000000000000000000000000000000",
                     "logIndex" => "0x0",
                     "removed" => true,
                     "topics" => [
                       "0x0148cba56e5d3a8d32fbcea206eae9e449ec0f0def4f642994b3edcd38561deb"
                     ],
                     "transactionHash" =>
                       "0xe776901f5d4049c63f3d464ee60162dd2a1f5c8d949e402e6b9f1d87705b9999",
                     "transactionIndex" => "0x0"
                   }
                 ]
               })}
            )

          %{"method" => "eth_subscribe", "params" => ["newHeads" | _]} ->
            Logger.debug("[server] sending newHeads eth_subscribe response")
            # mock eth_subscribe response
            Socket.Web.send!(
              client,
              {
                :text,
                Jason.encode!(%{
                  "id" => data["id"],
                  "jsonrpc" => "2.0",
                  # alchemy does not include this field in resp, so not including it here
                  # "method" => "eth_subscribe",
                  "result" => "0x8"
                })
              }
            )

            spawn(fn -> send_new_head(client, 2) end)

          %{"method" => "eth_subscribe", "params" => ["logs" | _]} ->
            Logger.debug("[server] sending logs eth_subscribe response")
            # mock eth_subscribe response
            Socket.Web.send!(
              client,
              {
                :text,
                Jason.encode!(%{
                  "id" => data["id"],
                  "jsonrpc" => "2.0",
                  # alchemy does not include this field in resp, so not including it here
                  # "method" => "eth_subscribe",
                  "result" => "0x9"
                })
              }
            )

            Logger.debug("[server] sending eth_subscription event")
            # mock event
            Socket.Web.send!(
              client,
              {:text,
               Jason.encode!(%{
                 "jsonrpc" => "2.0",
                 "method" => "eth_subscription",
                 "params" => %{
                   "result" => %{
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
                   },
                   "subscription" => "0x9"
                 }
               })}
            )

            # a second event which will be removed
            Socket.Web.send!(
              client,
              {:text,
               Jason.encode!(%{
                 "jsonrpc" => "2.0",
                 "method" => "eth_subscription",
                 "params" => %{
                   "result" => %{
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
                       "0xe776901f5d4049c63f3d464ee60162dd2a1f5c8d949e402e6b9f1d87705b9999",
                     "transactionIndex" => "0x0"
                   },
                   "subscription" => "0x9"
                 }
               })}
            )

            # remove the second event
            Socket.Web.send!(
              client,
              {:text,
               Jason.encode!(%{
                 "jsonrpc" => "2.0",
                 "method" => "eth_subscription",
                 "params" => %{
                   "result" => %{
                     "address" => "0x73d578371eb449726d727376393b02bb3b8e6a57",
                     "blockHash" =>
                       "0x6f917eb430805db84a84d4e71633d8dfc80f864cf06cc53bc65c6ea0fa0eab5d",
                     "blockNumber" => "0x1",
                     "data" =>
                       "0x0000000000000000000000000000000000000000000000000000000000000001000000000000000000000000959922be3caee4b8cd9a407cc3ac1c251c2007b10000000000000000000000000000000000000000000000000000000000000080000000000000000000000000000000000000000000000000000000000000001200000000000000000000000000000000000000000000000000000000000000034152420000000000000000000000000000000000000000000000000000000000",
                     "logIndex" => "0x0",
                     "removed" => true,
                     "topics" => [
                       "0x0148cba56e5d3a8d32fbcea206eae9e449ec0f0def4f642994b3edcd38561deb"
                     ],
                     "transactionHash" =>
                       "0xe776901f5d4049c63f3d464ee60162dd2a1f5c8d949e402e6b9f1d87705b9999",
                     "transactionIndex" => "0x0"
                   },
                   "subscription" => "0x9"
                 }
               })}
            )
        end

        client_handler(client)
    end
  end

  def send_new_head(client, block_number) do
    Logger.debug("[server] sending newHeads eth_subscription event")

    if is_nil(Port.info(client.socket)) do
      Logger.debug("[server] client disconnected")
    else
      # mock event
      Socket.Web.send!(
        client,
        {:text,
         Jason.encode!(%{
           "jsonrpc" => "2.0",
           "method" => "eth_subscription",
           "params" => %{
             "result" => %{
               "difficulty" => "0x15d9223a23aa",
               "extraData" => "0xd983010305844765746887676f312e342e328777696e646f7773",
               "gasLimit" => "0x47e7c4",
               "gasUsed" => "0x38658",
               "logsBloom" =>
                 "0x00000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000000",
               "miner" => "0xf8b483dba2c3b7176a3da549ad41a48bb3121069",
               "nonce" => "0x084149998194cc5f",
               "number" => W3WS.Util.to_hex(block_number),
               "parentHash" =>
                 "0x7736fab79e05dc611604d22470dadad26f56fe494421b5b333de816ce1f25701",
               "receiptRoot" =>
                 "0x2fab35823ad00c7bb388595cb46652fe7886e00660a01e867824d3dceb1c8d36",
               "sha3Uncles" =>
                 "0x1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347",
               "stateRoot" =>
                 "0xb3346685172db67de536d8765c43c31009d0eb3bd9c501c9be3229203f15f378",
               "timestamp" => "0x56ffeff8",
               "transactionsRoot" =>
                 "0x0167ffa60e3ebc0b080cdb95f7c0087dd6c0e61413140e39d94d3468d7c9689f"
             },
             "subscription" => "0x8"
           }
         })}
      )

      Process.sleep(10)

      if block_number < 10 do
        send_new_head(client, block_number + 1)
      end
    end
  end

  defp ws_loop(server) do
    Logger.debug("waiting for client connection")
    client = Socket.Web.accept!(server)
    Logger.debug("accepted client connection")
    # have to accept twice to actually accept the connection
    Socket.Web.accept!(client)
    spawn(fn -> client_handler(client) end)
    ws_loop(server)
  end

  def start(port) do
    spawn(fn ->
      server = Socket.Web.listen!(port)
      Logger.debug("listening on port #{port}")
      ws_loop(server)
    end)
  end
end
