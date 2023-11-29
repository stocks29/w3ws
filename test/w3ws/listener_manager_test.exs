defmodule W3WS.ListenerManagerTest do
  use ExUnit.Case, async: true
  doctest W3WS.Listener

  require Logger

  @port 9956

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

  alias W3WS.ListenerManager

  defp setup_ws_server(_tags) do
    pid = W3WS.WsServer.start(@port)
    on_exit(fn -> Process.exit(pid, :normal) end)

    {:ok, server: pid, uri: "ws://localhost:#{@port}"}
  end

  defp setup_listener_manager_with_listeners(%{uri: uri}) do
    test_pid = self()

    handler = fn env ->
      Logger.debug("[handler] Received env: #{inspect(env)}")
      send(test_pid, {:env, env})
    end

    subscription = [
      handler: handler,
      abi: @abi
    ]

    config = [
      uri: uri,
      subscriptions: [subscription]
    ]

    {:ok, manager} = ListenerManager.start_link(listeners: [config])
    on_exit(fn -> Process.exit(manager, :normal) end)

    {:ok, manager: manager}
  end

  defp setup_listener_manager_with_config(%{uri: uri}) do
    test_pid = self()

    handler = fn env ->
      Logger.debug("[handler] Received env: #{inspect(env)}")
      send(test_pid, {:env, env})
    end

    subscription = [
      handler: handler,
      abi: @abi
    ]

    config = [
      uri: uri,
      subscriptions: [subscription]
    ]

    Application.put_env(:test_app, W3WS, listeners: [config, config])

    {:ok, manager} = ListenerManager.start_link(otp_app: :test_app)
    on_exit(fn -> Process.exit(manager, :normal) end)

    {:ok, manager: manager}
  end

  defp maybe_setup_listener_manager(tags = %{listeners: _}) do
    setup_listener_manager_with_listeners(tags)
  end

  defp maybe_setup_listener_manager(tags) do
    setup_listener_manager_with_config(tags)
  end

  setup_all :setup_ws_server
  setup :maybe_setup_listener_manager

  @tag :listeners
  test "starts a listener for each given listener", %{manager: manager} do
    assert DynamicSupervisor.count_children(manager) == %{
             active: 1,
             workers: 1,
             supervisors: 0,
             specs: 1
           }
  end

  @tag :listeners
  test "starts listens which listen for and decodes events for each given listener" do
    assert_receive {:env, %W3WS.Env{}}, 500
  end

  test "starts a listener for each configured listener", %{manager: manager} do
    assert DynamicSupervisor.count_children(manager) == %{
             active: 2,
             workers: 2,
             supervisors: 0,
             specs: 2
           }
  end

  test "starts listeners which listen for and decode events for each configured listener" do
    assert_receive {:env, %W3WS.Env{}}, 500
  end
end
