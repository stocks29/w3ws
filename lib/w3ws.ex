defmodule W3WS do
  @moduledoc false

  @doc """
  Returns the configured JSON module.

  Defaults to `Jason`.
  """
  @spec json_module() :: module()
  def json_module do
    Application.get_env(:w3ws, :json_module, Jason)
  end
end
