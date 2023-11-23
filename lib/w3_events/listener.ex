defmodule W3Events.Listener do
  use Wind.Client, ping_timer: 10_000

  alias W3Events.{ABI, Message}

  require Logger

  def start_link(config) do
    uri = URI.new!(config.uri)

    config =
      config
      |> Map.put_new(:handler, W3Events.Handler.DefaultHandler)

    if (is_nil(config[:topics]) or length(config[:topics]) < 1) and
         (not is_nil(config[:abi]) or not is_nil(config[:abi_file])) do
      raise "Must specify at least one topic to decode events"
    end

    abi =
      cond do
        config[:abi_file] ->
          ABI.from_file(config[:abi_file])

        config[:abi] ->
          ABI.from_abi(config[:abi])

        true ->
          nil
      end

    topics = W3Events.ABI.encode_topics(config[:topics] || [], abi)

    config =
      Map.merge(config, %{
        abi: abi,
        topics: topics
      })

    Wind.Client.start_link(__MODULE__, uri: uri, config: config)
  end

  @impl Wind.Client
  def handle_connect(state) do
    config = Keyword.get(state.opts, :config)
    address = config[:address]
    topics = config[:topics]
    uri = config[:uri]

    Logger.metadata(address: address, topics: topics, uri: uri)

    message =
      topics
      |> Message.eth_subscribe_logs(id: 1, address: address)
      |> Message.encode!()

    {:reply, {:text, message}, state}
  end

  @impl Wind.Client
  def handle_frame({:text, message}, state) do
    message
    |> Jason.decode!()
    |> handle_decoded_frame(state.opts[:config])

    {:noreply, state}
  end

  defp handle_decoded_frame(message = %{"method" => "eth_subscription"}, config) do
    message
    |> W3Events.Env.from_eth_subscription()
    |> maybe_decode_event(config)
    |> apply_handler(config)
  end

  defp handle_decoded_frame(%{"id" => 1, "result" => subscription}, _config) do
    Logger.debug("subscription created: #{subscription}")
  end

  defp handle_decoded_frame(message, _config) do
    Logger.warning("unhandled message: #{inspect(message)}")
  end

  # we spawn processes (and don't link) so handler errors do not take down the listener process
  defp apply_handler(env, %{handler: {m, f, a}}), do: Process.spawn(m, f, [env | a], [])

  defp apply_handler(env, %{handler: handler}) when is_atom(handler),
    do: Process.spawn(handler, :handle, [env], [])

  defp apply_handler(env, %{handler: fun}) when is_function(fun),
    do: Process.spawn(fn -> fun.(env) end, [])

  defp maybe_decode_event(env, %{abi: nil}), do: env

  defp maybe_decode_event(env, %{abi: abi, topics: topics}) do
    case W3Events.ABI.decode_event(env.raw.data, abi, topics) do
      {:ok, selector, decoded_data} ->
        W3Events.Env.with_event(
          env,
          W3Events.Event.from_raw_event(env.raw, selector, decoded_data)
        )

      {:error, _} = err ->
        Logger.warning("failed to decode event: #{inspect(err)}")
        env
    end
  end
end
