defmodule W3WS.Fixtures.AbiFixtures do
  @abi [
    %{
      "name" => "TokenSupportChange",
      "type" => "event",
      "inputs" => [
        %{
          "name" => "supported",
          "indexed" => false,
          "internalType" => "bool",
          "type" => "bool"
        },
        %{
          "name" => "token",
          "indexed" => false,
          "internalType" => "address",
          "type" => "address"
        },
        %{
          "name" => "symbol",
          "indexed" => false,
          "internalType" => "string",
          "type" => "string"
        },
        %{
          "name" => "decimals",
          "indexed" => false,
          "internalType" => "uint8",
          "type" => "uint8"
        }
      ]
    }
  ]

  def abi_fixture() do
    @abi
  end
end
