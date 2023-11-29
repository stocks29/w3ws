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
                   }
                 ]
               })}
            )

          %{"method" => "eth_subscribe"} ->
            Logger.debug("[server] sending eth_subscribe response")
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
        end

        client_handler(client)
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
