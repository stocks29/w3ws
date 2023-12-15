defmodule W3WS.Handler.BlockRemovalHandler do
  @moduledoc """
  Handler which filters removed events by buffering received events until
  future blocks are created.

  Each time a new block is added the handler will check the queue and see
  if any events should be pushed to the given `:handler`. `:blocks`
  configures the number of blocks that must be created before an event
  is pushed to the `:handler`.

  If a `removed: true` event is received the handler will filter out the
  original event and the removed event, preventing them from being sent 
  to the `:handler`.

  In order to prevent memory usage from growing out of control, removed
  events are forgotten after `:removal_timeout` which defaults to 10s.

  This handler is meant to be composed with other handlers.

  ## Example

      {:ok, listener} = W3WS.Listener.start_link(
        uri: "http://localhost:8545",
        subscriptions: [
          [
            abi_files: ["path/to/abi.json"],
            handler: {W3WS.Handler.BlockRemovalHandler, 
              blocks: 12,
              handler: W3WS.Handler.DefaultHandler,
              removal_timeout: :timer.seconds(10),
              settled_threshold: :timer.seconds(5)},
            topics: ["Transfer"],
            address: "0x73d578371eb449726d727376393b02bb3b8e6a57"
          ]
        ]
      )
  """
  use W3WS.Handler.GenServerHandler

  require Logger

  defmodule State do
    @moduledoc false

    defstruct blocks: nil,
              handler: nil,
              handler_state: nil,
              last_event_at: nil,
              removal_timeout: nil,
              removals: MapSet.new(),
              rpc: nil,
              settled_threshold: nil,
              queue: []

    defp key(%Env{event: %Event{transaction_hash: hash, log_index: index}}) do
      {hash, index}
    end

    def was_removed?(%State{removals: removals}, env) do
      MapSet.member?(removals, key(env))
    end

    def record_removal(state, env = %Env{event: %Event{removed: true}}) do
      %State{state | removals: MapSet.put(state.removals, key(env))}
    end

    def forget_removal(state, env = %Env{event: %Event{removed: true}}) do
      %State{state | removals: MapSet.delete(state.removals, key(env))}
    end

    def enqueue(state = %__MODULE__{queue: queue}, env) do
      %State{state | queue: [env | queue]}
    end

    def extract_flushable(%State{blocks: blocks, queue: queue} = state, block_number) do
      # newest blocks are first in the list
      {queue, flushable} =
        Enum.split_while(queue, fn %Env{event: %Event{block_number: event_block_number}} ->
          block_number - event_block_number < blocks
        end)

      flushable =
        flushable
        |> Enum.reject(&was_removed?(state, &1))
        |> Enum.reverse()

      {flushable, %State{state | queue: queue}}
    end

    def set_last_event_at(state, last_event_at) do
      %State{state | last_event_at: last_event_at}
    end
  end

  @doc false
  @impl GenServer
  def init(args) do
    {:ok, state = %{rpc: rpc}} = super(args)

    blocks = Keyword.get(args, :blocks, 12)
    # TODO: better name?
    # how long to hold on to removals for
    removal_timeout = Keyword.get(args, :removal_timeout, 10_000)
    settled_threshold = Keyword.get(args, :settled_threshold, 5_000)

    # use rpc to eth_subscribe to new blocks
    {:ok, _response} = W3WS.Rpc.send_message(rpc, W3WS.Message.eth_subscribe_new_heads())

    {:ok,
     %State{
       struct(State, state)
       | blocks: blocks,
         removal_timeout: removal_timeout,
         settled_threshold: settled_threshold
     }}
  end

  @doc false
  @impl W3WS.Handler.GenServerHandler
  def is_settled?(%State{queue: []}), do: true
  def is_settled?(%State{last_event_at: nil}), do: true

  def is_settled?(%State{settled_threshold: settled_threshold, last_event_at: last_event_at}) do
    now() - last_event_at >= settled_threshold
  end

  defp now() do
    DateTime.utc_now()
    |> DateTime.to_unix(:millisecond)
  end

  @doc false
  @impl W3WS.Handler.GenServerHandler
  def handle_cast_event(env = %Env{event: %Event{removed: true}}, state) do
    state =
      state
      |> State.record_removal(env)
      |> State.set_last_event_at(now())

    schedule_forget(state, env)
    {:noreply, state}
  end

  def handle_cast_event(env = %Env{}, state) do
    Logger.debug("queueing event: #{inspect(env)}")

    state =
      state
      |> State.enqueue(env)
      |> State.set_last_event_at(now())

    {:noreply, state}
  end

  @doc false
  @impl GenServer
  def handle_info({:forget, env}, state) do
    state = State.forget_removal(state, env)
    {:noreply, state}
  end

  # notification of new block
  def handle_info(
        {:eth_subscription, %{"params" => %{"result" => %{"number" => block_number}}}},
        state = %State{handler: handler, handler_state: handler_state}
      ) do
    block_number = W3WS.Util.integer_from_hex(block_number)
    Logger.debug("new block: #{block_number}")
    {envs, state} = State.extract_flushable(state, block_number)

    Enum.each(envs, fn env ->
      Logger.debug("flushing non-removed event beyond threshold: #{inspect(env)}")
      W3WS.Handler.apply_handler(env, handler, handler_state)
    end)

    {:noreply, state}
  end

  @doc false
  @impl GenServer
  def terminate(_reason, %State{queue: queue = [_ | _]}) do
    Logger.warning("handler terminating: dropping #{length(queue)} events")
    :ok
  end

  def terminate(_reason, _state) do
    :ok
  end

  defp schedule_forget(%State{removal_timeout: timeout}, env) do
    Process.send_after(self(), {:forget, env}, timeout)
  end
end
