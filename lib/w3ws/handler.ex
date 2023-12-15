defmodule W3WS.Handler do
  @moduledoc """
  Base module for W3WS handlers

  `W3WS.Env`, `W3WS.Event` and `W3WS.RawEvent` are aliased into your handler
  automatically when you `use W3WS.Handler`.

  Define the `c:initialize/1` function to configure the handler state. This 
  state will be passed to `c:handle_event/2`. This callback is optional.

  Define the `c:handle_event/2` function to handle events in your handler. Events are not
  retried on error so be sure you have any necessary error handling or retry logic in place 
  if you cannot miss any events.

  Define the `c:settled?/1` function to determine if the handler has settled. This
  callback is optional. The default implementation always returns `true`.

  ## Example

      defmodule MyHandler do
        use W3WS.Handler

        @impl W3WS.Handler
        def initialize(_opts) do
          {:ok, nil}
        end

        @impl W3WS.Handler
        def handle_event(%Env{decoded?: true, event: %Event{} = event}, _state) do
          # inspect decoded events
          IO.inspect(event)
        end

        def handle_event(_env, _state) do
          # ignore non-decoded events
          :ok
        end

        @impl W3WS.Handler
        def settled?(_state), do: true
      end
  """

  @type t() ::
          module()
          | {module(), Keyword.t()}
          | (env :: W3WS.Env.t() -> any())
          | {module(), atom(), list()}
  @type state() :: any()

  @doc """
  Callback invoked to initialize the handler
  """
  @callback initialize(Keyword.t()) :: {:ok, state()}

  @doc """
  Callback invoked for each received event
  """
  @callback handle_event(env :: W3WS.Env.t(), state :: state()) :: any()

  @doc """
  Callback invoked to determine if the handler is settled
  """
  @callback settled?(state :: state()) :: boolean()

  defmacro __using__(_) do
    quote do
      @behaviour W3WS.Handler

      require Logger

      alias W3WS.{Env, Event, RawEvent}

      @doc """
      Initialize the handler
      """
      def initialize(_opts) do
        {:ok, nil}
      end

      defoverridable initialize: 1

      @doc """
      Determine if the handler is settled.
      """
      def settled?(state), do: true

      defoverridable settled?: 1

      @doc false
      def handle(%Env{} = env, opts) do
        handle_event(env, opts)
      end
    end
  end

  @doc """
  Initialize the handler.
  """
  @spec initialize(handler :: t()) :: {:ok, t(), state()} | {:error, any()}
  def initialize(handler, opts \\ [])

  @spec initialize(handler :: t(), opts :: Keyword.t()) :: {:ok, t(), state()} | {:error, any()}
  def initialize({module, init_opts}, opts) do
    opts = Keyword.merge(opts, init_opts)

    case module.initialize(opts) do
      {:ok, state} -> {:ok, module, state}
      err -> err
    end
  end

  def initialize(handler, _opts), do: {:ok, handler, nil}

  @doc """
  Determine if the handler is settled. This only applies to module-based handlers. For
  other handler types this always returns `true`.
  """
  @spec settled?(handler :: t(), state :: state()) :: boolean()
  def settled?(module, state) when is_atom(module) do
    module.settled?(state)
  end

  def settled?(_handler, _state), do: true

  @doc """
  Call the handler with the given event

  ## Examples

      iex> apply_handler(%W3WS.Env{}, fn _env -> :ok end, nil) |> is_pid()
      true

      iex> apply_handler(%W3WS.Env{}, W3WS.Handler.DefaultHandler, nil) |> is_pid()
      true

      iex> apply_handler(%W3WS.Env{}, {W3WS.Handler.DefaultHandler, :handle, []}, nil) |> is_pid()
      true

      iex> apply_handler(%W3WS.Env{}, "something", nil)
      ** (RuntimeError) Invalid handler: "something"
  """
  @spec apply_handler(
          env :: W3WS.Env.t(),
          handler :: W3WS.Handler.t(),
          state :: any()
        ) :: pid() | {pid(), reference()}

  # we spawn processes (and don't link) so handler errors do not take down the caller process

  # mfa handler
  def apply_handler(env, {m, f, a}, _state),
    do: Process.spawn(m, f, [env | a], [])

  # module based handler
  def apply_handler(env, {handler, _init_opts}, state),
    do: apply_handler(env, handler, state)

  # module based handler
  def apply_handler(env, handler, state) when is_atom(handler),
    do: Process.spawn(handler, :handle, [env, state], [])

  # anon function handler
  def apply_handler(env, fun, _state) when is_function(fun),
    do: Process.spawn(fn -> fun.(env) end, [])

  def apply_handler(_env, handler, _state) do
    raise "Invalid handler: #{inspect(handler)}"
  end
end
