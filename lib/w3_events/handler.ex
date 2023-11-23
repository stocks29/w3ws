defmodule W3Events.Handler do
  defmodule HandlerBehaviour do
    @callback handle(W3Events.Env.t()) :: any()
    @callback handle_event(W3Events.Env.t()) :: any()
  end

  defmacro __using__(_) do
    quote do
      @behaviour W3Events.Handler.HandlerBehaviour

      alias W3Events.{Env, Event, RawEvent}

      def handle(%Env{} = env) do
        handle_event(env)
      end

      def handle_event(%Env{} = env) do
        IO.inspect(env)
      end

      defoverridable handle_event: 1
    end
  end
end

defmodule W3Events.Handler.DefaultHandler do
  use W3Events.Handler
end
