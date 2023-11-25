defmodule W3WS.Handler do
  @moduledoc """
  Base module for W3WS handlers

  `W3WS.Env`, `W3WS.Event` and `W3WS.RawEvent` are aliased into your handler
  automatically when you `use W3WS.Handler`.

  Define the `c:handle_event/1` function to handle events in your handler. Events are not
  retried on error so be sure you have any necessary error handling or retry logic in place 
  if you cannot miss any events.

  ## Example

      defmodule MyHandler do
        use W3WS.Handler

        @impl W3WS.Handler
        def handle_event(%Env{decoded?: true, event: %Event{} = event}) do
          # inspect decoded events
          IO.inspect(event)
        end

        def handle_event(_env) do
          # ignore non-decoded events
          :ok
        end
      end
  """

  @doc """
  Callback invoked for each received event
  """
  @callback handle_event(W3WS.Env.t()) :: any()

  defmacro __using__(_) do
    quote do
      @behaviour W3WS.Handler

      require Logger

      alias W3WS.{Env, Event, RawEvent}

      @doc false
      def handle(%Env{} = env) do
        handle_event(env)
      end
    end
  end
end

defmodule W3WS.Handler.DefaultHandler do
  @moduledoc """
  Default W3WS handler which logs received events
  """
  use W3WS.Handler

  @doc """
  Simple handler which logs the received events
  """
  @impl W3WS.Handler
  def handle_event(%Env{} = env) do
    Logger.info("Received event: #{inspect(env)}")
  end
end
