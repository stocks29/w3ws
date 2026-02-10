defmodule W3WSTest do
  use ExUnit.Case
  doctest W3WS
  doctest_file("README.md")

  defmodule TestJsonModule do
    def encode!(value), do: {:encoded, value}
    def decode!(value), do: {:decoded, value}
  end

  test "json module is configurable" do
    previous = Application.get_env(:w3ws, :json_module)
    Application.put_env(:w3ws, :json_module, TestJsonModule)

    on_exit(fn ->
      if is_nil(previous) do
        Application.delete_env(:w3ws, :json_module)
      else
        Application.put_env(:w3ws, :json_module, previous)
      end
    end)

    assert W3WS.json_module() == TestJsonModule
    assert W3WS.Message.encode!(%{a: 1}) == {:encoded, %{a: 1}}
    assert W3WS.Message.decode!("{\"a\":1}") == {:decoded, "{\"a\":1}"}
  end
end
