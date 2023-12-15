defmodule W3WS.Listener do
  @moduledoc """
  W3WS Listener which handles the websocket connection and subscribes to
  configured ethereum events.

  If an ABI is provided and the event has a matching selector in the ABI
  the event will be decoded and passed to the handler in the `Env`. If no matching
  selector is found the non-decoded event will be passed to the handler.

  ABIs are subscription specific, so different ABIs can be used to decode
  different events using separate subscriptions.

  See `W3WS.Listener.start_link/1` for all configuration options.
  """

  use GenServer

  import W3WS.Message, only: [eth_block_number: 0, eth_subscribe_logs: 2, eth_unsubscribe: 1]

  require Logger

  @type subscription_config :: [
          abi: list(map()) | nil,
          abi_files: list(String.t()) | nil,
          context: map() | nil,
          handler: W3WS.Handler.t() | nil,
          topics: list(String.t()) | nil,
          address: String.t() | nil
        ]

  @type listener_config :: [
          uri: String.t(),
          block_ping: pos_integer() | nil,
          resubscribe: pos_integer() | nil,
          subscriptions: list(subscription_config()) | nil
        ]

  defmodule State do
    @moduledoc false

    def new(config, rpc) do
      config =
        config
        |> update_in([:subscriptions, Access.all()], &Enum.into(&1, %{}))
        |> Enum.into(%{})

      %{
        block: nil,
        block_ping_ref: nil,
        config: config,
        rpc: rpc
      }
    end

    def get_config(state) do
      get_in(state, [:config])
    end

    def get_uri(state) do
      get_in(state, [:config, :uri])
    end

    def get_block_ping_interval(state) do
      get_in(state, [:config, :block_ping])
    end

    def get_resubscribe_interval(state) do
      get_in(state, [:config, :resubscribe])
    end

    def get_subscription_by_id(state, sub_id) do
      state
      |> get_subscriptions()
      |> Enum.find(&(&1[:subscription_id] == sub_id))
    end

    def get_subscriptions(state) do
      get_in(state, [:config, :subscriptions])
    end

    def set_subscriptions(state, subscriptions) do
      put_in(state, [:config, :subscriptions], subscriptions)
    end

    def set_block_ping_ref(state, ref) do
      Map.put(state, :block_ping_ref, ref)
    end

    @doc """
    Set the block in the listener
    """
    def set_block(state, block) do
      Map.put(state, :block, block)
    end

    @doc """
    Get the block from the listener
    """
    def get_block(state) do
      Map.get(state, :block)
    end

    def update_subscriptions(state, fun) do
      subscriptions =
        state
        |> get_subscriptions()
        |> Enum.map(&fun.(&1))

      set_subscriptions(state, subscriptions)
    end
  end

  defmodule Subscription do
    @moduledoc false

    def get_context(subscription) do
      Map.get(subscription, :context, %{})
    end

    def set_subscription_id(subscription, sub_id) do
      Map.put(subscription, :subscription_id, sub_id)
    end

    def set_subscribe_ref(subscription, ref) do
      Map.put(subscription, :subscribe_ref, ref)
    end
  end

  @doc """
  Start the listener

  ## Examples

  Start a listener with no subscriptions

      {:ok, listener} = W3WS.Listener.start_link(uri: "http://localhost:8545")

  Start a listener with subscriptions

      {:ok, listener} = W3WS.Listener.start_link(
        uri: "http://localhost:8545",
        block_ping: :timer.seconds(10),
        resubscribe: :timer.minutes(5),
        subscriptions: [
          [
            abi_files: ["path/to/abi.json"],
            context: %{chain_id: 1},
            handler: W3WS.Handler.DefaultHandler,
            topics: ["Transfer"],
            address: "0x73d578371eb449726d727376393b02bb3b8e6a57"
          ]
        ]
      )
  """
  @spec start_link(listener_config()) :: {:ok, pid()}
  def start_link(config) do
    # default to one subscription which listens to everything
    subscriptions =
      (config[:subscriptions] || [[]])
      |> Enum.map(fn subscription ->
        abi = W3WS.Util.resolve_abi(subscription)
        topics = W3WS.ABI.encode_topics(subscription[:topics] || [], abi)

        subscription
        |> Keyword.merge(abi: abi, topics: topics)
        |> Keyword.put_new(:handler, W3WS.Handler.DefaultHandler)
      end)

    config = Keyword.put(config, :subscriptions, subscriptions)

    GenServer.start_link(__MODULE__, config)
  end

  @impl GenServer
  def init(config) do
    {:ok, rpc} = W3WS.Rpc.start_link(uri: config[:uri])

    # initialize handlers if necessary
    subscriptions =
      Enum.map(config[:subscriptions] || [], fn subscription ->
        {:ok, handler, handler_state} =
          Keyword.get(subscription, :handler)
          |> W3WS.Handler.initialize(rpc: rpc)

        Keyword.merge(subscription, handler: handler, handler_state: handler_state)
      end)

    config = Keyword.put(config, :subscriptions, subscriptions)

    state =
      State.new(config, rpc)
      |> subscribe_subscriptions()

    {:ok, state}
  end

  defp subscribe_subscriptions(state = %{config: %{uri: uri}, rpc: rpc}) do
    subscriptions = State.get_subscriptions(state)

    {state, subscriptions} =
      Enum.reduce(subscriptions, {state, []}, fn subscription, {state, subscriptions} ->
        address = subscription[:address]
        topics = subscription[:topics]

        ref = W3WS.Rpc.async_message(rpc, eth_subscribe_logs(topics, address: address))
        subscription = Subscription.set_subscribe_ref(subscription, ref)

        {state, [subscription | subscriptions]}
      end)

    if length(subscriptions) == 1 do
      [subscription] = subscriptions
      Logger.metadata(uri: uri, address: subscription[:address], topics: subscription[:topics])
    else
      Logger.metadata(uri: uri)
    end

    state
    |> State.set_subscriptions(subscriptions)
    |> maybe_schedule_helpers()
  end

  defp unsubscribe_subscriptions(state = %{rpc: rpc}) do
    State.update_subscriptions(state, fn
      subscription = %{subscription_id: sub_id} ->
        W3WS.Rpc.async_message(rpc, eth_unsubscribe(sub_id))

        # should these be nulled out here, or when the unsubscribe response is received?
        subscription
        |> Subscription.set_subscription_id(nil)
        |> Subscription.set_subscribe_ref(nil)
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

  @doc """
  Returns the last block number received by `block_ping`. If `block_ping` is not enabled
  or the first `block_ping` response hasn't been received yet, `nil` is returned.
  """
  def get_block(pid) do
    GenServer.call(pid, :block)
  end

  @impl GenServer
  def handle_call(:block, _from, state) do
    {:reply, State.get_block(state), state}
  end

  @impl GenServer
  def handle_info(:block_ping, state = %{rpc: rpc, block_ping_ref: nil}) do
    ref = W3WS.Rpc.async_message(rpc, eth_block_number())

    state =
      state
      |> State.set_block_ping_ref(ref)
      |> maybe_schedule_block_ping()

    {:noreply, state}
  end

  # there is still a pending block ping response so don't send another one, but schedule the next one
  def handle_info(:block_ping, state) do
    {:noreply, maybe_schedule_block_ping(state)}
  end

  def handle_info(:resubscribe, state) do
    state =
      state
      |> unsubscribe_subscriptions()
      |> subscribe_subscriptions()

    {:noreply, state}
  end

  def handle_info(
        {:eth_subscription,
         message = %{"method" => "eth_subscription", "params" => %{"subscription" => sub_id}}},
        state
      ) do
    sub = State.get_subscription_by_id(state, sub_id)
    context = Subscription.get_context(sub)

    message
    |> W3WS.Env.from_eth_subscription(context)
    |> W3WS.Util.decode_apply(sub[:abi], sub[:handler], sub[:handler_state])

    {:noreply, state}
  end

  def handle_info(
        {:eth_response, ref, %{"result" => result}, _req},
        %{block_ping_ref: ref} = state
      ) do
    # this is a block ping response
    block_number = W3WS.Util.integer_from_hex(result)
    Logger.info("[BlockPing] current block: #{block_number} (#{result})")
    {:noreply, State.set_block(state, block_number)}
  end

  def handle_info({:eth_response, ref, response, request}, state) do
    Logger.debug("received response\n#{inspect(request)}\n#{inspect(response)}")
    state = handle_pending_response(request, response, ref, state)
    {:noreply, state}
  end

  # a little weird because the request is an atom map and the response is a string map

  # handle eth_subscribe response
  defp handle_pending_response(
         %{method: :eth_subscribe},
         %{"result" => sub_id},
         ref,
         state
       ) do
    Logger.debug("created subscription: #{sub_id}")

    State.update_subscriptions(state, fn subscription ->
      case subscription[:subscribe_ref] do
        ^ref -> Map.put(subscription, :subscription_id, sub_id)
        _ -> subscription
      end
    end)
  end

  # handle eth_unsubscribe response
  defp handle_pending_response(
         %{method: :eth_unsubscribe, params: [sub_id]},
         %{"result" => true},
         _ref,
         state
       ) do
    Logger.debug("destroyed subscription: #{sub_id}")
    state
  end

  defp handle_pending_response(
         %{method: :eth_unsubscribe, params: [sub_id]},
         %{"result" => false},
         _ref,
         state
       ) do
    Logger.warning("failed to destory subscription: #{sub_id}")
    state
  end
end
