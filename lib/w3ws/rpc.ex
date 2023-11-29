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
  Send a message to the RPC server and asynchronously receive
  the response as a message to the calling process.

  ## Examples

      {:ok, receipt} = Rpc.async_message(rpc, eth_block_number())
      
      receive do
        {:eth_response, ^receipt, response} -> IO.inspect(response)
      end
  """
  @spec async_message(rpc(), map()) :: pos_integer()
  def async_message(rpc, message) do
    GenServer.call(rpc, {:async, message})
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
  def handle_call({:send, message}, {from, ref}, state) do
    state = send_msg(message, {:sync, from, ref}, state)
    {:noreply, state}
  end

  # we use references instead of request ids to allow for a single
  # process to handle responses easily from multiple rpc servers
  # and to make it easier to handle the state where the rpc server
  # has not connected to the ws yet.
  def handle_call({:async, message}, {from, _ref}, state) do
    ref = make_ref()
    state = send_msg(message, {:async, from, ref}, state)
    {:reply, ref, state}
  end

  @impl W3WS.RpcBase
  def handle_response(response, _request, {:sync, from, ref}, state) do
    GenServer.reply({from, ref}, {:ok, response})
    state
  end

  def handle_response(response, _request, {:async, from, ref}, state) do
    send(from, {:eth_response, ref, response})
    state
  end

  @impl W3WS.RpcBase
  def handle_subscription(response, from, state) do
    send(from, {:eth_subscription, response})
    state
  end
end
