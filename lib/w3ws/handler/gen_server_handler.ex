defmodule W3WS.Handler.GenServerHandler do
  @moduledoc """
  A GenServer implementation of `W3WS.Handler`. Useful for building out a 
  handler with a GenServer.

  See `W3WS.Handler.TimedRemovalHandler` and `W3WS.Handler.BlockRemovalHandler`
  for examples.

  This handler monitors the `W3WS.Rpc` passed to `initialize/1`. If the 
  rpc goes down, this handler will terminate.

  The handler will be linked to the process which calls `initialize/1`.
  Typically this will be a `W3WS.Listener` or a `W3WS.Replayer`. If the
  handler crashes the caller will go down as well due to the link.
  """

  require Logger

  @doc """
  Handle an event cast to the GenServer
  """
  @callback handle_cast_event(env :: Env.t(), state :: map()) :: {:noreply, map()}

  @doc """
  Determine if the handler is settled based on the GenServer state
  """
  @callback is_settled?(state :: map()) :: boolean()

  defmacro __using__(_) do
    quote do
      use W3WS.Handler
      use GenServer

      @behaviour W3WS.Handler.GenServerHandler

      @doc """
      Initialize the handler. Requires a `t:W3WS.Rpc.rpc/0` 
      to be passed in the `args`
      """
      @impl W3WS.Handler
      def initialize(args) do
        {:ok, handler} = start_link(args)
        {:ok, handler}
      end

      @doc """
      Handle an event. Casts the event to the GenServer.
      """
      @impl W3WS.Handler
      def handle_event(env, handler) do
        GenServer.cast(handler, {:handle_event, env})
      end

      defp start_link(args) do
        GenServer.start_link(__MODULE__, args)
      end

      @doc """
      GenServer init callback.
      """
      @impl GenServer
      def init(args) do
        W3WS.Handler.GenServerHandler.init(args, __MODULE__)
      end

      defoverridable init: 1

      @doc """
      Handle a cast event.
      """
      def handle_cast_event(env, state) do
        W3WS.Handler.GenServerHandler.handle_cast_event(env, state, __MODULE__)
      end

      defoverridable handle_cast_event: 2

      @doc """
      GenServer handle cast callback.
      """
      @impl GenServer
      def handle_cast({:handle_event, env}, state) do
        handle_cast_event(env, state)
      end

      # rpc process went down so terminate this process
      @impl GenServer
      def handle_info({:DOWN, _ref, :process, rpc, reason}, state = %{rpc: rpc}) do
        Logger.debug("handler stopping: rpc process went down with reason: #{inspect(reason)}")
        {:stop, :normal, state}
      end

      @doc """
      Returns `true` if the handler has settled. 
      """
      @impl W3WS.Handler
      def settled?(handler) do
        GenServer.call(handler, :settled?)
      end

      def is_settled?(_state), do: true

      defoverridable is_settled?: 1

      @impl GenServer
      def handle_call(:settled?, _from, state) do
        {:reply, is_settled?(state), state}
      end

      defoverridable handle_call: 3
    end
  end

  @doc false
  def init(args, _module) do
    rpc = Keyword.get(args, :rpc)

    # monitor rpc process since we depend on receiving new blocks from it
    # if it goes down we need to stop this process so the parent can also stop and restart
    Process.monitor(rpc)

    {:ok, handler, handler_state} =
      args
      |> Keyword.get(:handler, W3WS.Handler.DefaultHandler)
      |> W3WS.Handler.initialize(rpc: rpc)

    {:ok,
     %{
       handler: handler,
       handler_state: handler_state,
       rpc: rpc
     }}
  end

  @doc false
  def handle_cast_event(env, state = %{handler: handler, handler_state: handler_state}, _module) do
    W3WS.Handler.apply_handler(env, handler, handler_state)
    {:noreply, state}
  end
end
