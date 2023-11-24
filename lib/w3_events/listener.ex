defmodule W3Events.Listener do
  use Wind.Client, ping_timer: 10_000

  alias W3Events.{ABI, Message}

  require Logger

  defmodule State do
    def get_config(state) do
      get_in(state, [:opts, :config])
    end

    def get_uri(state) do
      get_in(state, [:opts, :config, :uri])
    end

    def get_block_ping_interval(state) do
      get_in(state, [:opts, :config, :block_ping])
    end

    def get_resubscribe_interval(state) do
      get_in(state, [:opts, :config, :resubscribe])
    end

    def get_subscription_by_id(state, sub_id) do
      state
      |> get_subscriptions()
      |> Enum.find(&(&1[:subscription_id] == sub_id))
    end

    def get_subscriptions(state) do
      get_in(state, [:opts, :config, :subscriptions])
    end

    def set_subscriptions(state, subscriptions) do
      put_in(state, [:opts, :config, :subscriptions], subscriptions)
    end

    def get_id(state) do
      get_in(state, [:listener, :id]) || 0
    end

    def set_id(state, id) do
      case state[:listener] do
        %{id: _id} -> put_in(state, [:listener, :id], id)
        nil -> Map.put(state, :listener, default_listener_state(id))
      end
    end

    def next_id(state) do
      new_id = get_id(state) + 1
      {new_id, set_id(state, new_id)}
    end

    def next_block_ping_id(state) do
      {id, state} = next_id(state)
      {id, put_in(state, [:listener, :block_ping_id], id)}
    end

    defp default_listener_state(id), do: %{id: id, block_ping_id: nil}

    def update_subscriptions(state, fun) do
      subscriptions =
        state
        |> get_subscriptions()
        |> Enum.map(&fun.(&1))

      set_subscriptions(state, subscriptions)
    end
  end

  defmodule Subscription do
    def set_subscription_id(subscription, sub_id) do
      Map.put(subscription, :subscription_id, sub_id)
    end

    def set_message_id(subscription, message_id) do
      Map.put(subscription, :message_id, message_id)
    end
  end

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
    {:noreply, subscribe_subscriptions(state)}
  end

  defp subscribe_subscriptions(state) do
    subscriptions = State.get_subscriptions(state)
    uri = State.get_uri(state)
    next_id = State.get_id(state) + 1

    ids = Stream.iterate(next_id, &(&1 + 1))

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

    state
    |> State.set_subscriptions(subscriptions)
    |> State.set_id(max_id)
    |> maybe_schedule_helpers()
  end

  defp unsubscribe_subscriptions(state) do
    State.update_subscriptions(state, fn subscription = %{subscription_id: sub_id} ->
      Message.eth_unsubscribe(sub_id)
      |> Message.encode!()
      |> send_text_frame(state)

      subscription
      |> Subscription.set_subscription_id(nil)
      |> Subscription.set_message_id(nil)
    end)
  end

  defp maybe_schedule_helpers(state) do
    state
    |> maybe_schedule_block_ping()
    |> maybe_schedule_resubscribe()
  end

  defp maybe_schedule_block_ping(state) do
    maybe_schedule(&State.get_block_ping_interval/1, :block_ping, state)
  end

  defp maybe_schedule_resubscribe(state) do
    maybe_schedule(&State.get_resubscribe_interval/1, :resubscribe, state)
  end

  defp maybe_schedule(interval_fun, event, state) do
    if interval = interval_fun.(state) do
      Process.send_after(self(), event, interval)
    end

    state
  end

  @impl GenServer
  def handle_info(:block_ping, state) do
    {id, state} = State.next_block_ping_id(state)

    Message.eth_block_number(id: id)
    |> Message.encode!()
    |> send_text_frame(state)

    {:noreply, maybe_schedule_block_ping(state)}
  end

  def handle_info(:resubscribe, state) do
    state =
      state
      |> unsubscribe_subscriptions()
      |> subscribe_subscriptions()

    {:noreply, state}
  end

  def handle_info(message, state) do
    super(message, state)
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
    subscription = State.get_subscription_by_id(state, sub_id)

    message
    |> W3Events.Env.from_eth_subscription()
    |> maybe_decode_event(subscription)
    |> apply_handler(subscription.handler)

    state
  end

  defp handle_decoded_frame(
         %{"id" => id, "result" => result},
         %{listener: %{block_ping_id: id}} = state
       ) do
    # this is a block ping response
    Logger.info(
      "[BlockPing] current block: #{W3Events.Util.integer_from_hex(result)} (#{result})"
    )

    state
  end

  defp handle_decoded_frame(%{"id" => _id, "result" => result}, state) when is_boolean(result) do
    Logger.debug("Destroyed subscription: #{result}")
    state
  end

  defp handle_decoded_frame(%{"id" => id, "result" => sub_id}, state) do
    Logger.debug("Created subscription: #{sub_id}")

    State.update_subscriptions(state, fn subscription ->
      case subscription[:message_id] do
        ^id -> Map.put(subscription, :subscription_id, sub_id)
        _ -> subscription
      end
    end)
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
