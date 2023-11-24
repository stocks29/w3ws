defmodule W3WS.Handler do
  defmodule HandlerBehaviour do
    @callback handle(W3WS.Env.t()) :: any()
    @callback handle_event(W3WS.Env.t()) :: any()
  end

  defmacro __using__(_) do
    quote do
      @behaviour W3WS.Handler.HandlerBehaviour

      require Logger

      alias W3WS.{Env, Event, RawEvent}

      def handle(%Env{} = env) do
        handle_event(env)
      end

      def handle_event(%Env{} = env) do
        Logger.info("Received event: #{inspect(env)}")
      end

      defoverridable handle_event: 1
    end
  end
end

defmodule W3WS.Handler.DefaultHandler do
  use W3WS.Handler
end
