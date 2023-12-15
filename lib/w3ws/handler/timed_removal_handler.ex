defmodule W3WS.Handler.TimedRemovalHandler do
  @moduledoc """
  Handler which filters out removed events using a time-delayed buffer. 

  Events are delayed until they are older than the configured `:delay`. 
  If a `removed: true` event is received before the `:delay` has passed, 
  the handler will not pass the event to the underlying `:handler`.

  This handler is meant to be composed with other handlers.

  ## Example

      {:ok, listener} = W3WS.Listener.start_link(
        uri: "http://localhost:8545",
        subscriptions: [
          [
            abi_files: ["path/to/abi.json"],
            handler: {W3WS.Handler.TimedRemovalHandler, 
              delay: :timer.seconds(2),
              handler: W3WS.Handler.DefaultHandler},
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

    defstruct delay: nil,
              handler: nil,
              handler_state: nil,
              removals: MapSet.new(),
              rpc: nil,
              queued: 0

    def new(state, delay) do
      %State{struct(State, state) | delay: delay}
    end

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

    def increment_queued(state = %State{queued: queued}) do
      %State{state | queued: queued + 1}
    end

    def decrement_queued(state = %State{queued: queued}) do
      %State{state | queued: queued - 1}
    end
  end

  @doc false
  @impl GenServer
  def init(args) do
    delay = Keyword.get(args, :delay, 2_000)
    {:ok, state} = super(args)
    {:ok, State.new(state, delay)}
  end

  @doc false
  @impl W3WS.Handler.GenServerHandler
  def handle_cast_event(env = %Env{event: %Event{removed: true}}, state) do
    state = State.record_removal(state, env)
    schedule_forget(state, env)
    {:noreply, state}
  end

  def handle_cast_event(env = %Env{}, state) do
    schedule_send(state, env)
    state = State.increment_queued(state)
    {:noreply, state}
  end

  @doc false
  @impl GenServer
  def handle_info(
        {:send_event, env},
        state = %State{handler: handler, handler_state: handler_state}
      ) do
    if State.was_removed?(state, env) do
      Logger.info("dropping removed event: #{inspect(env)}")
    else
      W3WS.Handler.apply_handler(env, handler, handler_state)
    end

    state = State.decrement_queued(state)

    {:noreply, state}
  end

  def handle_info({:forget, env}, state) do
    state = State.forget_removal(state, env)
    {:noreply, state}
  end

  @doc false
  @impl W3WS.Handler.GenServerHandler
  def is_settled?(%State{queued: queued}), do: queued == 0

  defp schedule_send(%State{delay: delay}, env) do
    Process.send_after(self(), {:send_event, env}, delay)
  end

  defp schedule_forget(%State{delay: delay}, env) do
    Process.send_after(self(), {:forget, env}, delay * 5)
  end
end
