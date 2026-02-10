defmodule W3WS.RpcBase do
  @moduledoc false

  require Logger

  defmodule RpcState do
    @moduledoc false

    @key :base_rpc

    def get_key(), do: @key

    def setup(state) when is_map_key(state, @key), do: state

    def setup(state) do
      Map.put(state, @key, default_state())
    end

    def get_id(state) do
      get_in(state, [@key, :id])
    end

    def set_id(state, id) do
      put_in(state, [@key, :id], id)
    end

    def next_id(state) do
      new_id = get_id(state) + 1
      {new_id, set_id(state, new_id)}
    end

    # id is the last id sent
    # queued is for tracking requests from before the connection was established
    # pending is for tracking pending requests
    def default_state() do
      %{id: 0, pending: %{}, queued: [], subscriptions: %{}, connected?: false}
    end

    @doc """
    Add a pending request
    """
    def add_pending(state, pending = %{id: id}, from) do
      state
      |> set_id(id)
      |> update_in([@key, :pending], &Map.put(&1, id, {from, pending}))
    end

    @doc """
    Get a pending request
    """
    def get_pending(state, id) do
      get_in(state, [@key, :pending, id])
    end

    @doc """
    Call when a response is received to remove a pending request
    """
    def remove_pending(state, id) do
      update_in(state, [@key, :pending], &Map.delete(&1, id))
    end

    def add_queued(state, request) do
      state
      |> setup()
      |> update_in([@key, :queued], &[request | &1])
    end

    def get_and_clear_queued(state) do
      # reverse the queue so message are sent in same order
      queued = get_in(state, [@key, :queued])
      {Enum.reverse(queued), put_in(state, [@key, :queued], [])}
    end

    def connected(state) do
      put_in(state, [@key, :connected?], true)
    end

    @subscriptions [@key, :subscriptions]

    def get_subscriptions(state) do
      get_in(state, @subscriptions)
    end

    def get_subscription(state, subscription) do
      get_in(state, @subscriptions ++ [subscription])
    end

    def get_subscriptions_for_process(state, pid) do
      state
      |> get_subscriptions()
      |> Enum.filter(fn {_subscription, {process, _ref}} -> pid == process end)
      |> Enum.into(%{})
      |> Map.keys()
    end

    # common case is receiving messages so we key on the subscription
    def add_subscription(state, subscription, pid, monitor_ref) do
      update_in(state, @subscriptions, &Map.put(&1, subscription, {pid, monitor_ref}))
    end

    # remove all subscriptions for a process. called when the process stops.
    def remove_subscriptions(state, pid) do
      subscriptions =
        get_subscriptions(state)
        |> Enum.reject(fn {_subscription, {process, _ref}} -> pid == process end)
        |> Enum.into(%{})

      update_in(state, @subscriptions, subscriptions)
    end

    def remove_subscription(state, subscription) do
      update_in(state, @subscriptions, &Map.delete(&1, subscription))
    end
  end

  @type from :: {:async | :sync, pid(), reference()}

  @callback handle_response(
              message :: map(),
              request :: map(),
              from :: from(),
              state :: map()
            ) :: map()

  @callback handle_subscription(
              message :: map(),
              from :: pid(),
              state :: map()
            ) :: map()

  defmacro __using__(_opts) do
    quote do
      @behaviour W3WS.RpcBase

      # TODO: maybe make this a configurable option
      use Wind.Client, ping_timer: 30_000

      alias W3WS.RpcBase.RpcState
      alias W3WS.Message

      @impl Wind.Client
      def handle_connect(state) do
        {queued, state} =
          state
          |> RpcState.setup()
          |> RpcState.connected()
          |> RpcState.get_and_clear_queued()

        case queued do
          [] -> :ok
          [_ | _] -> Logger.debug("sending queued requests")
        end

        state =
          Enum.reduce(queued, state, fn {from, message}, state ->
            send_msg(message, from, state)
          end)

        {:noreply, state}
      end

      defp send_text_frame(text, state) do
        case send_frame({:text, text}, state) do
          {:noreply, state} -> state
        end
      end

      defp send_msg(msg, from, state)

      # not yet connected, so queue the message
      defp send_msg(message = %{id: _id}, from, state)
           when not is_map_key(state, :base_rpc) or not state.base_rpc.connected? do
        Logger.debug("queuing request")
        RpcState.add_queued(state, {from, message})
      end

      # already connected and non-subscription so send it
      defp send_msg(message = %{id: _id}, from, state) do
        {id, state} = RpcState.next_id(state)
        message = Message.set_id(message, id)
        state = RpcState.add_pending(state, message, from)
        Logger.debug("sending request #{inspect(message)}")

        message
        |> Message.encode!()
        |> send_text_frame(state)
      end

      @impl Wind.Client
      def handle_frame({:text, message}, state) do
        W3WS.RpcBase.handle_frame({:text, message}, state, __MODULE__)
      end

      @doc """
      Stop the RPC server
      """
      def stop(rpc) do
        GenServer.stop(rpc)
      end

      @doc false
      def handle_info({:DOWN, _ref, :process, pid, _reason}, state) do
        state = W3WS.RpcBase.handle_down_process(pid, &send_msg/3, state)
        {:noreply, state}
      end

      def handle_info(message, state) do
        super(message, state)
      end

      defoverridable handle_info: 2
    end
  end

  def start_link(module, args) do
    uri = URI.new!(args[:uri])
    Wind.Client.start_link(module, uri: uri)
  end

  def handle_frame({:text, message}, state, module) do
    state =
      message
      |> W3WS.json_module().decode!()
      |> handle_decoded_frame(state, module)

    {:noreply, state}
  end

  # this clause handles responses to pending requests for which the caller
  # is blocked waiting on the response, or administrative messages our process sent
  defp handle_decoded_frame(
         %{"id" => id} = response,
         state = %{base_rpc: %{pending: pending}},
         module
       )
       when is_map_key(pending, id) do
    # original request and sender
    {from = {_type, pid, _ref}, request} = pending[id]

    Logger.debug("received response #{inspect(response)} for request #{inspect(request)}")

    state = update_subs(response, request, from, state)

    state =
      if pid == self() do
        # this is a response to an administrative event that we (not a client) sent.
        # ie eth_unsubscribe due to dead process. we don't want to call handle_response 
        # when this module unsubscribed because the subscribed process died.
        state
      else
        # call a response handler which the subscription module can override
        module.handle_response(response, request, from, state)
      end

    state
    |> RpcState.remove_pending(id)
  end

  # this clause handles subscription events
  defp handle_decoded_frame(
         %{"method" => "eth_subscription", "params" => %{"subscription" => subscription}} =
           response,
         state = %{base_rpc: %{subscriptions: subscriptions}},
         module
       )
       when is_map_key(subscriptions, subscription) do
    {from, _monitor_ref} = RpcState.get_subscription(state, subscription)
    module.handle_subscription(response, from, state)

    Logger.debug("received subscription #{inspect(response)}")
    state
  end

  # this is the response from setting up a subscription, so we need to record the
  # subscription mapping to the process that requested it.
  # alchemy does not send the `method` field in the response so we need to match
  # against the original request that was sent.
  defp update_subs(
         %{"result" => subscription},
         %{method: :eth_subscribe},
         {_type, pid, _ref},
         state
       ) do
    Logger.info("tracking subscription #{subscription} for #{inspect(pid)}")
    monitor_ref = Process.monitor(pid)
    RpcState.add_subscription(state, subscription, pid, monitor_ref)
  end

  defp update_subs(%{"method" => "eth_unsubscribe"}, %{params: [subscription]}, from, state) do
    {_pid, monitor_ref} = RpcState.get_subscription(state, subscription)
    Logger.info("stopped tracking subscription #{subscription} for #{inspect(from)}")
    Process.demonitor(monitor_ref)
    RpcState.remove_subscription(state, subscription)
  end

  defp update_subs(_response, _request, _from, state), do: state

  # called when a process exits. we just send the eth_unsubscribe
  # message here and let the response remove the subscriptions
  # from the state
  def handle_down_process(pid, send_msg, state) do
    Logger.debug("unsubscribing because the subscribed process exited")
    subscriptions = RpcState.get_subscriptions_for_process(state, pid)

    Enum.reduce(subscriptions, state, fn subscription, state ->
      # send these messages from ourself so we can avoid trying to
      # reply to a dead process when the unsubscribe response is received
      send_msg.(W3WS.Message.eth_unsubscribe(subscription), {:admin, self(), nil}, state)
    end)
  end
end
