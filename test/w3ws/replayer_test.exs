defmodule W3WS.ReplayerTest do
  use ExUnit.Case, async: true
  doctest W3WS.Replayer

  require Logger
  alias W3WS.Replayer

  @port 9958

  @abi W3WS.Fixtures.AbiFixtures.abi_fixture()

  setup_all :setup_ws_server
  setup :setup_rpc
  setup :setup_handler

  test "replays events", %{uri: uri, handler: handler, get_events: get_events} do
    Replayer.replay(
      uri: uri,
      from_block: 1,
      chunk_size: 5,
      chunk_sleep: 0,
      replays: [
        [handler: handler]
      ]
    )

    events = get_events.()
    assert length(events) == 2
  end

  test "decodes events when ABI present", %{uri: uri, handler: handler, get_events: get_events} do
    Replayer.replay(
      uri: uri,
      from_block: 1,
      chunk_size: 5,
      chunk_sleep: 0,
      replays: [
        [
          abi: @abi,
          handler: handler
        ]
      ]
    )

    events = get_events.()
    assert length(events) > 0
    assert Enum.all?(events, fn env -> env.decoded? end)
  end

  defp setup_ws_server(_tags) do
    pid = W3WS.WsServer.start(@port)
    on_exit(fn -> Process.exit(pid, :normal) end)

    {:ok, server: pid, uri: "ws://localhost:#{@port}"}
  end

  defp setup_rpc(%{uri: uri}) do
    {:ok, rpc} = W3WS.Rpc.start_link(uri: uri)
    on_exit(fn -> Process.exit(rpc, :normal) end)

    {:ok, rpc: rpc}
  end

  defp setup_handler(_tags) do
    {:ok, agent} = Agent.start_link(fn -> [] end)

    handler = fn env ->
      Agent.update(agent, fn events -> [env | events] end)
    end

    get_events = fn ->
      Agent.get(agent, fn events -> events end)
    end

    {:ok, handler: handler, get_events: get_events}
  end
end
