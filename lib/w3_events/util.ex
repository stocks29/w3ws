defmodule W3Events.Util do
  def to_hex(binary), do: "0x" <> Base.encode16(binary, case: :lower)

  def from_hex("0x" <> hex), do: Base.decode16!(hex, case: :lower)
  def from_hex(hex), do: Base.decode16!(hex, case: :lower)

  def integer_from_hex("0x" <> hex) do
    {int, ""} = Integer.parse(hex, 16)
    int
  end

  def keccak(binary, opts \\ []) do
    result = ExKeccak.hash_256(binary)

    case Keyword.get(opts, :hex?, false) do
      true -> to_hex(result)
      false -> result
    end
  end
end
