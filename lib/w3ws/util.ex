defmodule W3WS.Util do
  @moduledoc """
  Utility functions
  """

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
end
