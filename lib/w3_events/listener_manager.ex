defmodule W3Events.ListenerManager do
  use DynamicSupervisor

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
  def init(_args) do
    DynamicSupervisor.init(strategy: :one_for_one)
  end

  @doc """
  Add a listener to the ListenerManager
  """
  def add_listener(pid, config) do
    DynamicSupervisor.start_child(pid, %{
      id: :crypto.hash(:sha, :erlang.term_to_binary(config)),
      start: {W3Events.Listener, :start_link, [config]}
    })
  end

  @doc """
  Remove a listener from the ListenerManager
  """
  def remove_listener(pid, child) do
    DynamicSupervisor.terminate_child(pid, child)
  end

  defp get_listeners_from_config(otp_app) do
    otp_app
    |> Application.get_env(W3Events)
    |> maybe_get(:listeners, [])
  end

  defp maybe_get(config, key, default)
  defp maybe_get(nil, _key, default), do: default
  defp maybe_get(config, key, default), do: Keyword.get(config, key, default)
end
