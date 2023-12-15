defmodule W3WS.Handler.DefaultHandler do
  @moduledoc """
  Default W3WS handler which logs received events
  """
  use W3WS.Handler

  @doc """
  Simple handler which logs the received events
  """
  @impl W3WS.Handler
  def handle_event(%Env{} = env, _state) do
    Logger.info("received event: #{inspect(env)}")
  end
end
