defmodule W3WS.Rpc do
  @moduledoc """
  W3WS RPC Server

  This is useful for making arbitary requests to the JSON-RPC server over a 
  websocket. This module ignores the `id` field (if any) in given message as
  it maintains it's own sequence.
  """

  use W3WS.RpcBase

  require Logger

  @type rpc :: pid()

  @doc """
  Start an RPC server

  ## Examples

      {:ok, rpc} = W3WS.Rpc.start_link(uri: "ws://localhost:8545")

  """
  @spec start_link(uri: String.t()) :: {:ok, rpc()}
  def start_link(args) do
    W3WS.RpcBase.start_link(__MODULE__, args)
  end

  @doc """
  Send a message to the RPC server.

  This is a synchronous function which returns the response from the JSON-RPC server, 
  but does not block the RPC process.

  ## Examples

      {:ok, result} = W3WS.Rpc.send_message(rpc, W3WS.Message.eth_block_number())
      
  """
  @spec send_message(rpc(), map()) :: {:ok, map()} | {:error, any()}
  def send_message(rpc, message) do
    GenServer.call(rpc, {:send, message})
  end

  @impl GenServer
  def handle_call({:send, message}, from, state) do
    state = send_msg(message, from, state)
    {:noreply, state}
  end

  @impl W3WS.RpcBase
  def handle_response(response, _request, from, state) do
    GenServer.reply(from, {:ok, response})
    state
  end

  @impl W3WS.RpcBase
  def handle_subscription(response, from, state) do
    send(from, {:eth_subscription, response})
    state
  end
end
