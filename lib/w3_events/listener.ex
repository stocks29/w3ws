defmodule W3Events.Listener do
  use Wind.Client, ping_timer: 10_000

  alias W3Events.{ABI, Message}

  require Logger

  def start_link(config) do
    uri = URI.new!(config.uri)

    # default to one subscription which listens to everything
    subscriptions =
      (config[:subscriptions] || [%{}])
      |> Enum.map(fn subscription ->
        abi =
          cond do
            subscription[:abi_files] ->
              ABI.from_files(subscription[:abi_files])

            subscription[:abi] ->
              ABI.from_abi(subscription[:abi])

            true ->
              nil
          end

        topics = W3Events.ABI.encode_topics(subscription[:topics] || [], abi)

        subscription
        |> Map.merge(%{abi: abi, topics: topics})
        |> Map.put_new(:handler, W3Events.Handler.DefaultHandler)
      end)

    config = Map.put(config, :subscriptions, subscriptions)

    Wind.Client.start_link(__MODULE__, uri: uri, config: config)
  end

  @impl Wind.Client
  def handle_connect(state) do
    config = Keyword.get(state.opts, :config)
    subscriptions = config[:subscriptions]
    uri = config[:uri]

    ids = Stream.iterate(1, &(&1 + 1))

    subscriptions =
      Enum.zip_reduce(subscriptions, ids, [], fn subscription, id, subscriptions ->
        address = subscription[:address]
        topics = subscription[:topics]

        topics
        |> Message.eth_subscribe_logs(id: id, address: address)
        |> Message.encode!()
        |> send_text_frame(state)

        subscription = Map.put(subscription, :message_id, id)

        [subscription | subscriptions]
      end)

    if length(subscriptions) == 1 do
      [subscription] = subscriptions
      Logger.metadata(uri: uri, address: subscription[:address], topics: subscription[:topics])
    else
      Logger.metadata(uri: uri)
    end

    max_id =
      subscriptions
      |> Enum.map(fn %{message_id: id} -> id end)
      |> Enum.max(&>=/2, fn -> 0 end)

    state =
      state
      |> put_in([:opts, :config, :subscriptions], subscriptions)
      |> Map.put(:listener, %{id: max_id})

    {:noreply, state}
  end

  @impl Wind.Client
  def handle_frame({:text, message}, state) do
    state =
      message
      |> Jason.decode!()
      |> handle_decoded_frame(state)

    {:noreply, state}
  end

  defp handle_decoded_frame(
         message = %{"method" => "eth_subscription", "params" => %{"subscription" => sub_id}},
         state
       ) do
    config = state.opts[:config]
    subscription = Enum.find(config[:subscriptions], &(&1[:subscription_id] == sub_id))

    message
    |> W3Events.Env.from_eth_subscription()
    |> maybe_decode_event(subscription)
    |> apply_handler(subscription.handler)

    state
  end

  defp handle_decoded_frame(%{"id" => id, "result" => sub_id}, state) do
    Logger.debug("subscription created: #{sub_id}")

    subscriptions =
      Enum.map(state.opts[:config][:subscriptions], fn subscription ->
        case subscription[:message_id] do
          ^id -> Map.put(subscription, :subscription_id, sub_id)
          _ -> subscription
        end
      end)

    put_in(state, [:opts, :config, :subscriptions], subscriptions)
  end

  defp handle_decoded_frame(message, state) do
    Logger.warning("unhandled message: #{inspect(message)}")

    state
  end

  # we spawn processes (and don't link) so handler errors do not take down the listener process
  defp apply_handler(env, {m, f, a}), do: Process.spawn(m, f, [env | a], [])

  defp apply_handler(env, handler) when is_atom(handler),
    do: Process.spawn(handler, :handle, [env], [])

  defp apply_handler(env, fun) when is_function(fun),
    do: Process.spawn(fn -> fun.(env) end, [])

  defp maybe_decode_event(env, %{abi: nil}) do
    W3Events.Env.with_event(env, W3Events.Event.from_raw_event(env.raw, nil, nil))
  end

  defp maybe_decode_event(env, %{abi: abi}) do
    {selector, decoded_data} =
      case W3Events.ABI.decode_event(env.raw.data, abi, env.raw.topics) do
        {:ok, selector, decoded_data} ->
          {selector, decoded_data}

        {:error, _} = err ->
          Logger.warning("unable to decode event error=#{inspect(err)} event=#{inspect(env.raw)}")
          {nil, nil}
      end

    W3Events.Env.with_event(env, W3Events.Event.from_raw_event(env.raw, selector, decoded_data))
  end

  defp send_text_frame(text, state), do: send_frame({:text, text}, state)
end
