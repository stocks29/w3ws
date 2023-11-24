defmodule W3WSTest do
  use ExUnit.Case
  doctest W3WS

  test "greets the world" do
    assert W3WS.hello() == :world
  end
end
