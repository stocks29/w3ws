# W3WS

Ethereum websocket library for Elixir

![w3ws logo](./logo.jpg)

The current focus of this project is on consuming events from the Ethereum 
blockchain over websockets.

## Goals

1. Provide an easy to use library for listening to ethereum events via websockets.
2. Completely abstract away the need to deal with processes in Elixir.
3. Support loading of ABIs at runtime.
4. Support multiple subscriptions through a single listener.
5. Support different ABIs for each subscription.
6. Automatically decode events when a corresponding ABI is available.
7. Always pass the event to the handler, even when it cannot be decoded.
8. Support starting of multiple listeners pointing to different websocket urls.
9. Support integration with distributed supervisors for clustered environments.

## Installation

The package can be installed by adding `w3ws` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:w3ws, "~> 0.4"}
  ]
end
```

## Usage

Documentation can be found at <https://hexdocs.pm/w3ws>.

### JSON Module

W3WS uses `Jason` by default. You can override the JSON implementation with:

```elixir
config :w3ws, json_module: Jason
```

The configured module must provide `encode!/1` and `decode!/1`.

### Event Listener

Configure the listeners for your application:

```elixir
# in your config.exs
config :my_app, W3WS, listeners: [
  [
    # the uri of the ethereum jsonrpc websocket server
    uri: "ws://localhost:8545",

    # enable block ping every 10 seconds. this will cause the listener to
    # fetch and log the current block every 10 seconds. the last fetched block 
    # will be available from `Listener.get_block/1`. Defaults to `nil` which
    # disables block ping.
    block_ping: :timer.seconds(10),

    # a helper setting for dealing with finicky local nodes (ie hardhat) where the
    # server stops sending subscription events after some time. setting this to
    # a number of milliseconds will cause the listener to unsubscribe and resubscribe
    # all configured subscriptions every `resubscribe` milliseconds. Defaults to `nil`
    # which disables resubscribing.
    # https://github.com/NomicFoundation/hardhat/issues/2053
    resubscribe: :timer.minutes(5),

    # subscriptions to setup on this websocket connection. each listener
    # can support many subscriptions and will call the corresponding handler
    # for each subscription event, using the provided subscription abi, if any,
    # to decode events for the subscription.
    subscriptions: [
      [
        # one of `abi` or `abi_files` is necessary to decode events.
        # neither are required if you jsut want to listen for encoded events.
        abi: abi,                        # decoded json abi
        abi_files: ["path/to/abi.json"], # list of paths to abi json files

        # an optional `context` to provide in the `W3WS.Env` struct for any events
        # received from this subscription. Defaults to `%{}`.
        context: %{chain_id: 1},

        # handler to call for each received event. can be either a module which `use`s 
        # `W3WS.Handler` and defines a `c:W3WS.Handler.handle_event/2` function, an 
        # anonymous function which accepts a `%W3WS.Env{}` struct, or an MFA tuple. 
        # In the MFA tuple case  the arguments will be a `%W3WS.Env{}` struct followed
        # by any arguments provided.
        # defaults to `W3WS.Handler.DefaultHandler` which logs received events.
        handler: {W3WS.Handler.BlockRemovalHandler,
                    blocks: 12,
                    handler: MyApp.Handler},

        # a list of log event topics to subscribe to for the given subscription. this is
        # optional. not passing `:topics` will subscribe to all log events. See
        # https://ethereum.org/en/developers/tutorials/using-websockets/#eth-subscribe
        # documentation for more details. If an abi is provided you can use short-hand event
        # names or event signatures (e.g. `Transfer(address,address,uint256)`) as topics. 
        # Short-hand is also supported in nested "or" topics. Regardless of providing an abi,
        # you can always use hex topics (e.g. 
        # `0x0148cba56e5d3a8d32fbcea206eae9e449ec0f0def4f642994b3edcd38561deb`).
        topics: ["Transfer"],

        # address to limit the subscription to. this is optional. if not provided
        # events will be received for all addresses.
        address: "0x73d578371eb449726d727376393b02bb3b8e6a57"
      ]
    ]
  ]
]
```

Add the `ListenerManager` to your supervision tree:

```elixir
# in your application.ex
children = [
  {W3WS.ListenerManager, otp_app: :my_app}
]

Supervisor.start_link(children, strategy: :one_for_one)
```

### Replay Events

Replay events for a set of blocks.

```elixir
W3WS.Replayer.replay(
  abi_files: abi_paths,
  uri: uri,
  from_block: 1_000_000,
  chunk_size: 10_000,
  chunk_sleep: 5_000,
  handler: MyApp.Handler,
  replays: [
    [address: "0x0000000000000000000000000000000000000000", topics: ["Transfer"]],
    [address: "0x9999999999999999999999999999999999999999", topics: ["Mint"]]
    [
      address: "0x5555555555555555555555555555555555555555", 
      from_block: 1_500_000,
      handler: MyApp.SwapHandler,
      topics: ["Swap"]
    ]
  ]
)
```

Add a replay task to your task supervisor:

```elixir
W3WS.Replayer.start(
  supervisor,
  abi_files: abi_paths,
  uri: uri,
  from_block: 1_000_000,
  chunk_size: 10_000,
  chunk_sleep: 5_000,
  handler: MyApp.Handler,
  replays: [
    [address: "0x0000000000000000000000000000000000000000", topics: ["Transfer"]],
    [address: "0x9999999999999999999999999999999999999999", topics: ["Mint"]]
    [
      address: "0x5555555555555555555555555555555555555555", 
      from_block: 1_500_000,
      handler: MyApp.SwapHandler,
      topics: ["Swap"]
    ]
  ]
)
```

### Handler

Define a handler:

```elixir
defmodule MyApp.Handler do
  use W3WS.Handler

  @impl W3WS.Handler
  def handle_event(
        %Env{
            decoded?: true, 
            event: %Event{name: "Transfer", data: %{"from" => from}}
        },
        _state
    ) do
    Logger.debug("received Transfer event from #{from}")
  end
end
```

Each handler is executed in an unlinked process so handler errors will not bring down 
the calling process. Events are not retried on failure so be sure your handler
properly handles errors or queues event processing into a resilient framework. The
listener does not wait on the handler to complete. If serial processing of events is 
important to you, you will need to handle this yourself. The return value from the 
handler is ignored.

#### Removed Events

There are a few composable handlers included which can be used to filter out removed events:

- `W3WS.Handler.TimedRemovalHandler`
- `W3WS.Handler.BlockRemovalHandler`

### RPC Calls

It is also possible to use the underlying `W3WS.Rpc` API directly. This is a lower-level library
which does no ABI decoding. If you want to subscribe to logs and receive decoded events use
`W3WS.Listener` or `W3WS.ListenerManager`. If you want to get past decoded events use `W3WS.Replayer`.

Perform synchonous calls:

```elixir
{:ok, rpc} = W3WS.Rpc.new(uri: "ws://localhost:8545")
{:ok, %{"result" => block_number}} = W3WS.Rpc.send_message(rpc, W3WS.Message.eth_block_number())
```

Perform asynchronous calls:

```elixir
{:ok, rpc} = W3WS.Rpc.start_link(uri: "ws://localhost:8545")
receipt = W3WS.Rpc.async_message(rpc, eth_block_number())

receive do
  {:eth_response, ^receipt, response, request} ->
    Logger.debug("received response")
end
```

Subscribe to events:

```elixir
{:ok, rpc} = W3WS.Rpc.start_link(uri: "ws://localhost:8545")

# synchronous subscribe
{:ok, %{"result" => subscription}} = W3WS.Rpc.send_message(rpc, W3WS.Message.eth_subscribe_logs([]))

# or async subscribe
receipt = W3WS.Rpc.async_message(rpc, W3WS.Message.eth_subscribe_logs([]))

receive do
  {:eth_subscription, event} ->
    Logger.debug("received subscription")
end
```

See the [documentation](https://hexdocs.pm/w3ws) for additional usage.

## Caveats

- Because of the way listener processes are identified, if you start two `W3WS.Listener`s
  with identical configuration through one or more `W3WS.ListenerManager`s, the second 
  `W3WS.Listener` will likely fail to start. If you start them directly with 
  `W3WS.Listener.start_link/1` this will not be a problem.

## Project State

- There is a decent test suite which exercises much of the library functionality.
- Testing has been done against a real Ethereum node (hardhat and alchemy).
- No performance testing has been done. If you have a performance problem, please
  open an issue. If you do performance testing and want to report results for 
  inclusion here please open an issue.
- This library is under active development and is subject to change without notice.
  - Semantic versioning will not be followed until the library is stable.
