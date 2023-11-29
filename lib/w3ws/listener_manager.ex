defmodule W3WS.ListenerManager do
  @moduledoc """
  W3WS Listener Manager. Starts up and manages listeners using provided `:listeners`
  and/or by loading listener config from the given `:otp_app`.
  """

  use DynamicSupervisor

  @type manager_config :: [
          listeners: list(W3WS.Listener.listener_config()) | nil,
          otp_app: atom() | nil
        ]

  @doc """
  Start a listener manager

  ## Examples

  Start a `W3WS.ListenerManager` with one directly configured listener

      {:ok, manager} = W3WS.ListenerManager.start_link(
        listeners: [%{uri: "ws://localhost:8545"}]
      )

  Start a `W3WS.ListenerManager` with application configuration

      # in config/config.exs
      config :my_app, W3WS, listeners: [
        [uri: "ws://localhost:8545"]
      ]

      # somewhere in your app
      {:ok, manager} = W3WS.ListenerManager.start_link(otp_app: :my_app)

  See `W3WS.Listener.start_link/1` for more configuration options.
  """
  @spec start_link(manager_config()) :: {:ok, pid()}
  def start_link(args) do
    otp_app = Keyword.get(args, :otp_app)
    passed_configs = Keyword.get(args, :listeners, [])
    config_configs = get_listeners_from_config(otp_app)
    configs = config_configs ++ passed_configs

    {:ok, pid} = DynamicSupervisor.start_link(__MODULE__, [])

    # start configured listeners
    Enum.each(configs, fn config ->
      {:ok, _child} = add_listener(pid, config)
    end)

    {:ok, pid}
  end

  @impl DynamicSupervisor
  @doc false
  def init(_args) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Add a listener to the ListenerManager

  ## Examples

      {:ok, listener} = W3WS.ListenerManager.add_listener(
        uri: "ws://localhost:8545",
        subscriptions: [
          [
            abi_files: [path_to_abi_file],
     	      handler: MyApp.EventHandler,
            address: "0xf39Fd6e51aad88F6F4ce6aB8827279cffFb92266"
          ]
     	  ]
      )
  """
  @spec add_listener(manager :: pid(), config :: W3WS.Listener.listener_config()) :: {:ok, pid()}
  def add_listener(pid, config) do
    DynamicSupervisor.start_child(pid, %{
      id: :crypto.hash(:sha, :erlang.term_to_binary(config)),
      start: {W3WS.Listener, :start_link, [config]}
    })
  end

  @doc """
  Remove a listener from the ListenerManager

  ## Examples

      W3WS.ListenerManager.remove_listener(manager, listener)
  """
  @spec remove_listener(manager :: pid(), listener :: pid()) :: :ok
  def remove_listener(pid, listener) do
    DynamicSupervisor.terminate_child(pid, listener)
  end

  defp get_listeners_from_config(otp_app) do
    otp_app
    |> Application.get_env(W3WS)
    |> maybe_get(:listeners, [])
  end

  defp maybe_get(config, key, default)
  defp maybe_get(nil, _key, default), do: default
  defp maybe_get(config, key, default), do: Keyword.get(config, key, default)
end
