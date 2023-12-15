defmodule W3WS.Replayer do
  @moduledoc """
  A `Task` that replays past events.

  `W3WS.Replayer` executes each replay in parallel. Each replay fetches 
  the logs, decodes if possible, and calls the handler with each event. 
  Each replay iterates from the `from_block` to the `to_block` using 
  `chunk_size` number of blocks. When the replayer has reached the 
  `to_block` it will stop and shutdown.

  If an ABI is provided and the event has a matching selector in the ABI
  the event will be decoded and passed to the handler in the `Env`. If no matching
  selector is found the non-decoded event will be passed to the handler.

  ABIs are replay specific, so different ABIs can be used to decode
  different events using separate replays.

  ## Replayer Options

  Options for the replayer.

  - `:abi` - (optional) ABI used to decode events.
  - `:abi_files` - (optional) List of paths to ABI files for decoding events.
  - `:chunk_size` - (optional) Number of blocks to fetch at a time. See replay options.
  - `:chunk_sleep` - (optional) Number of milliseconds to sleep between chunks. Defaults to 10 seconds.
  - `:context` - (optional) Context to pass to the handler. Defaults to `%{}`.
  - `:from_block` - (optional) Starting block to replay from. See replayer options.
  - `:handler` - (optional) Handler to call with the event. Defaults to logging the event.
  - `:to_block` - (optional) Ending block to replay to. See replayer options.
  - `:replays` - List of replays to execute. See replay options.
  - `:uri` - Websocket JSON-RPC server URI to connect to.

  ## Replay Options

  Common options are inherited from the replayer options if present but can be overridden
  for a specific replay. This allows you to define common arguments for the entire replayer
  and then only specify differentiating args for each replay.

      W3WS.Replayer.replay(
        abi_files: abi_paths,
        uri: uri,
        from_block: 1_000_000,
        chunk_size: 10_000,
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

  - `:abi` - (optional) ABI used to decode events.
  - `:abi_files` - (optional) List of paths to ABI files for decoding events.
  - `:address` - (optional) Address to filter events.
  - `:chunk_size` - (optional) Number of blocks to fetch at a time. Defaults to `5_000`.
  - `:chunk_sleep` - (optional) Number of milliseconds to sleep between chunks. Defaults to 10 seconds.
  - `:context` - (optional) Context to pass to the handler. Defaults to `%{}`.
  - `:from_block` - (optional) Starting block to replay from. Defaults to `{:before_current, 500_000}` which will resolve to 500k blocks before the current block.
  - `:handler` - (optional) Handler to call with the event. Defaults to `W3WS.Handler.DefaultHandler`.
  - `:to_block` - (optional) Ending block to replay to. Defaults to the current block at the time the replayer starts.
  - `:topics` - (optional) List of topics to filter events.
  """

  require Logger

  @type chunk_size :: pos_integer()
  @type from_block :: pos_integer() | String.t() | {:before_current, pos_integer()}
  @type to_block :: pos_integer() | String.t()

  @type replay_args :: [
          abi: list(map()) | nil,
          abi_files: list(String.t()) | nil,
          address: String.t() | nil,
          chunk_size: chunk_size() | nil,
          chunk_sleep: pos_integer() | nil,
          context: map() | nil,
          from_block: from_block() | nil,
          handler: W3WS.Handler.t() | nil,
          to_block: to_block() | nil,
          topics: list(String.t()) | nil
        ]

  @type replayer_args :: [
          abi: list(map()) | nil,
          abi_files: list(String.t()) | nil,
          chunk_size: chunk_size() | nil,
          chunk_sleep: pos_integer() | nil,
          context: map() | nil,
          from_block: from_block() | nil,
          handler: W3WS.Handler.t() | nil,
          to_block: to_block() | nil,
          replays: list(replay_args()),
          uri: String.t()
        ]

  @doc """
  Start a replayer task linked to the given supervisor. The task is not linked 
  to the caller. Defaults `:restart` to `:transient` but a different option can
  be passed.

  ## Examples

      {:ok, task} = W3WS.Replayer.start(MyApp.TaskSupervisor, args)
  """
  @spec start(
          supervisor :: Supervisor.supervisor(),
          args :: replayer_args(),
          options :: keyword()
        ) ::
          DynamicSupervisor.on_start_child()
  def start(supervisor, args, options \\ []) do
    options = Keyword.put_new(options, :restart, :transient)
    Task.Supervisor.start_child(supervisor, task_fn(args), options)
  end

  @doc """
  Run the replayer linked to the caller, waiting until it completes.

  ## Examples

      W3WS.Replayer.replay(args)
  """
  @spec replay(args :: replayer_args(), timeout :: timeout()) :: :ok
  def replay(args, timeout \\ :infinity) do
    task = async(args)
    Task.await(task, timeout)
  end

  @doc """
  Run then replayer linked to the caller. The returned task **must be awaited**.

  ## Examples

      replayer = W3WS.Replayer.async(args)
      do_other_stuff()
      Task.await(replayer)
  """
  @spec async(args :: replayer_args()) :: Task.t() | {:error, [term()]}
  def async(args) do
    Task.async(task_fn(args))
  end

  defp task_fn(args) do
    {replays, args} = Keyword.pop(args, :replays)

    fn ->
      {:ok, rpc} = W3WS.Rpc.start_link(uri: args[:uri])

      tasks =
        Enum.map(replays || [], fn replay ->
          Logger.debug("starting replay #{inspect(replay)}")

          replay =
            args
            |> Keyword.merge(replay)
            |> Keyword.put(:rpc, rpc)

          Task.async(W3WS.Replayer.ReplayerTask, :run, [replay])
        end)

      Logger.debug("waiting for replays to complete")
      Task.await_many(tasks, :infinity)
      W3WS.Rpc.stop(rpc)
      Logger.debug("replays complete")

      :ok
    end
  end

  defmodule ReplayerTask do
    @moduledoc false

    import W3WS.Message, only: [eth_block_number: 0, eth_get_logs: 1]
    import W3WS.Util, only: [integer_from_hex: 1]

    use Task, restart: :transient

    @spec start_link(args :: W3WS.Replayer.replay_args()) :: {:ok, pid()}
    def start_link(args) do
      Task.start_link(__MODULE__, :run, [args])
    end

    @doc """
    Replayer Task
    """
    @spec run(args :: W3WS.Replayer.replay_args()) :: any()
    def run(args) do
      rpc = Keyword.get_lazy(args, :rpc, fn -> start_rpc(args[:uri]) end)
      {:ok, %{"result" => current_block_hex}} = W3WS.Rpc.send_message(rpc, eth_block_number())
      current_block = W3WS.Util.integer_from_hex(current_block_hex)

      # normalize blocks to integers so we can do any necessary math to resolve
      from_block =
        Keyword.get(args, :from_block)
        |> resolve_from_block(current_block)

      to_block =
        Keyword.get(args, :to_block)
        |> resolve_to_block(current_block)

      context = Keyword.get(args, :context, %{})
      handler = Keyword.get(args, :handler, W3WS.Handler.DefaultHandler)
      chunk_size = Keyword.get(args, :chunk_size, 5_000)
      chunk_sleep = Keyword.get(args, :chunk_sleep, 10_000)
      abi = W3WS.Util.resolve_abi(args)

      {:ok, handler, handler_state} = W3WS.Handler.initialize(handler, rpc: rpc)

      topics =
        Keyword.get(args, :topics, [])
        |> W3WS.ABI.encode_topics(abi)

      base_args =
        args
        |> Keyword.take([:address])
        |> Keyword.put(:topics, topics)

      # Do the replay
      from_block..to_block//chunk_size
      |> Stream.chunk_every(2, 1)
      |> Stream.map(&normalize_chunk(&1, to_block))
      |> Enum.each(fn [start_block, end_block] ->
        args =
          Keyword.merge(base_args,
            from_block: W3WS.Util.to_hex(start_block),
            to_block: W3WS.Util.to_hex(end_block)
          )

        do_replay(rpc, args, handler, handler_state, abi, context)

        if end_block < to_block and chunk_sleep > 0 do
          Process.sleep(chunk_sleep)
        end
      end)

      wait_until_handler_settled(handler, handler_state)
    end

    defp wait_until_handler_settled(handler, state) do
      if W3WS.Handler.settled?(handler, state) do
        :ok
      else
        Logger.debug("waiting for handler to settle")
        Process.sleep(1_000)
        wait_until_handler_settled(handler, state)
      end
    end

    @spec do_replay(
            rpc :: W3WS.Rpc.t(),
            args :: W3WS.Replayer.replay_args(),
            handler :: W3WS.Handler.t(),
            handler_state :: any(),
            abi :: list(%ABI.FunctionSelector{}) | nil,
            context :: map()
          ) :: :ok
    defp do_replay(rpc, args, handler, handler_state, abi, context) do
      # get the logs
      {:ok, %{"result" => logs}} = W3WS.Rpc.send_message(rpc, eth_get_logs(args))

      # call the handler for each event
      Enum.each(logs, fn log ->
        log
        |> W3WS.Env.from_log(context)
        |> W3WS.Util.decode_apply(abi, handler, handler_state)
      end)
    end

    defp normalize_chunk([_start, _end] = chunk, _to_block), do: chunk
    defp normalize_chunk([start], to_block), do: [start, to_block]

    defp start_rpc(uri) do
      {:ok, rpc} = W3WS.Rpc.start_link(uri: uri)
      rpc
    end

    defp resolve_to_block(nil, current), do: current
    defp resolve_to_block("0x" <> _ = to, _current), do: integer_from_hex(to)
    defp resolve_to_block(to, _current) when is_integer(to), do: to

    defp resolve_from_block(nil, current),
      do: resolve_from_block({:before_current, 500_000}, current)

    defp resolve_from_block({:before_current, blocks}, current), do: max(0, current - blocks)
    defp resolve_from_block("0x" <> _rest = from, _current), do: integer_from_hex(from)
    defp resolve_from_block(from, _current) when is_integer(from), do: from
  end
end
