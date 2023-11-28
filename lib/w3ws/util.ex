defmodule W3WS.Util do
  @moduledoc """
  Utility functions
  """

  require Logger

  @doc """
  Convert a binary to hex

  ## Examples

      iex> to_hex(<<1, 2, 3>>)
      "0x010203"
  """
  @spec to_hex(binary()) :: String.t()
  def to_hex(binary), do: "0x" <> Base.encode16(binary, case: :lower)

  @doc """
  Convert a hex string to a binary

  ## Examples

      iex> from_hex("0x010203")
      <<1, 2, 3>>

      iex> from_hex("0x")
      ""

      iex> from_hex("")
      ""
  """
  @spec from_hex(String.t()) :: binary()
  def from_hex("0x" <> hex), do: from_hex(hex)
  def from_hex(hex), do: Base.decode16!(hex, case: :lower)

  @doc """
  Convert a hex string to an integer

  ## Examples

      iex> integer_from_hex("0x7")
      7
  """
  @spec integer_from_hex(String.t()) :: integer()
  def integer_from_hex("0x" <> hex) do
    {int, ""} = Integer.parse(hex, 16)
    int
  end

  @doc """
  Calculate the keccak256 hash of a binary, optionally encoding as hex

  ## Examples

      iex> keccak("foo", hex?: true)
      "0x41b1a0649752af1b28b3dc29a1556eee781e4a4c3a1f7f53f90fa834de098c4d"
  """
  @spec keccak(binary, Keyword.t()) :: String.t()
  def keccak(binary, opts \\ []) do
    result = ExKeccak.hash_256(binary)

    case Keyword.get(opts, :hex?, false) do
      true -> to_hex(result)
      false -> result
    end
  end

  @doc """
  Call the handler with the given event

  ## Examples

      iex> apply_handler(%W3WS.Env{}, fn _env -> :ok end) |> is_pid()
      true

      iex> apply_handler(%W3WS.Env{}, W3WS.Handler.DefaultHandler) |> is_pid()
      true

      iex> apply_handler(%W3WS.Env{}, {W3WS.Handler.DefaultHandler, :handle, []}) |> is_pid()
      true

      iex> apply_handler(%W3WS.Env{}, "something")
      ** (RuntimeError) Invalid handler: "something"
  """
  @spec apply_handler(
          env :: W3WS.Env.t(),
          handler :: W3WS.Handler.t()
        ) :: pid() | {pid(), reference()}

  # we spawn processes (and don't link) so handler errors do not take down the caller process
  def apply_handler(env, {m, f, a}), do: Process.spawn(m, f, [env | a], [])

  def apply_handler(env, handler) when is_atom(handler),
    do: Process.spawn(handler, :handle, [env], [])

  def apply_handler(env, fun) when is_function(fun),
    do: Process.spawn(fn -> fun.(env) end, [])

  def apply_handler(_env, handler) do
    raise "Invalid handler: #{inspect(handler)}"
  end

  @doc """
  Try to decode an event if an ABI is present
  """
  @spec maybe_decode_event(W3WS.Env.t(), W3WS.ABI.t() | nil) :: W3WS.Env.t()
  def maybe_decode_event(env, nil) do
    W3WS.Env.with_event(env, W3WS.Event.from_raw_event(env.raw, nil, nil))
  end

  def maybe_decode_event(env, abi) do
    {selector, decoded_data} =
      case W3WS.ABI.decode_event(env.raw.data, abi, env.raw.topics) do
        {:ok, selector, decoded_data} ->
          {selector, decoded_data}

        {:error, _} = err ->
          Logger.warning("unable to decode event error=#{inspect(err)} event=#{inspect(env.raw)}")
          {nil, nil}
      end

    W3WS.Env.with_event(env, W3WS.Event.from_raw_event(env.raw, selector, decoded_data))
  end

  @doc """
  Try to decode the event with the given ABI and apply the handler.
  The handler is always called, even if the event could not be 
  decoded.
  """
  @spec decode_apply(W3WS.Env.t(), W3WS.ABI.t() | nil, W3WS.Handler.t()) ::
          pid() | {pid(), reference()}
  def decode_apply(env, abi, handler) do
    env
    |> maybe_decode_event(abi)
    |> apply_handler(handler)
  end

  @doc """
  Resolve the ABI from the given options

  ## Examples

      iex> resolve_abi(abi: [])
      []

      iex> resolve_abi(abi: nil)
      nil

      iex> resolve_abi(abi: [], abi_files: ["./test/support/files/test_abi.json"])
      [
        %ABI.FunctionSelector{
          function: "Transfer", 
          method_id: <<221, 242, 82, 173>>, 
          type: :event, 
          inputs_indexed: [false, false, false], 
          state_mutability: nil, 
          input_names: ["from", "to", "value"], 
          types: [:address, :address, {:uint, 256}], 
          returns: [], 
          return_names: []
        }
      ]
  """
  def resolve_abi(opts) do
    cond do
      opts[:abi_files] ->
        W3WS.ABI.from_files(opts[:abi_files])

      opts[:abi] ->
        W3WS.ABI.from_abi(opts[:abi])

      true ->
        nil
    end
  end
end
