# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Explorer.Chain.Shinerium.SystemCallTest do
  use ExUnit.Case, async: true

  alias Explorer.Chain.{Data, Hash}
  alias Explorer.Chain.Shinerium.SystemCall

  # The node's requests encoded by Go (test/support/fixture/shinerium/system_calls.go).
  @vectors "#{File.cwd!()}/test/support/fixture/shinerium/system_calls.json"

  @addresses %{
    "ValidatorBond" => "0x0000000000000000000000000000000000000102",
    "BinaryRegistry" => "0x0000000000000000000000000000000000000103",
    "AccountKeys" => "0x0000000000000000000000000000000000000106",
    "Council" => "0x0000000000000000000000000000000000000107"
  }

  @identity String.duplicate(<<0x11>>, 32)
  @signer String.duplicate(<<0x12>>, 32)
  @binary String.duplicate(<<0xAA>>, 32)

  # What each vector of the fixture decodes to, beyond its contract.
  @expected %{
    {"ValidatorBond", "deposit"} => %{code: 1, name: "deposit", identity: @identity},
    {"ValidatorBond", "requestExit"} => %{code: 2, name: "requestExit", identity: @identity},
    {"ValidatorBond", "beginRelease"} => %{code: 3, name: "beginRelease", identity: @identity},
    {"ValidatorBond", "withdraw"} => %{code: 4, name: "withdraw", identity: @identity},
    {"ValidatorBond", "reportConflict"} => %{code: 5, name: "reportConflict", identity: @identity},
    {"ValidatorBond", "signingReset"} => %{code: 6, name: "signingReset", identity: @identity},
    {"ValidatorBond", "setName"} => %{code: 7, name: "setName", identity: @identity},
    {"ValidatorBond", "transferOwner"} => %{code: 8, name: "transferOwner", identity: @identity},
    {"ValidatorBond", "topUp"} => %{code: 9, name: "topUp", identity: @identity},
    # a number the explorer does not know: no name and no fields read
    {"ValidatorBond", "unknown"} => %{code: 12, name: nil},
    {"Council", "proposeTransfer"} => %{code: 1, name: "propose", identity: @identity, kind: "transfer"},
    {"Council", "proposeCollateral"} => %{code: 1, name: "propose", identity: @identity, kind: "collateral"},
    {"Council", "voteNo"} => %{code: 2, name: "vote", identity: @identity, proposal: 7, choice: "no"},
    {"Council", "voteYesSmall"} => %{code: 2, name: "vote", identity: @identity, proposal: 7, choice: "yes"},
    # an execution is signed by nobody
    {"Council", "execute"} => %{code: 3, name: "execute", proposal: 7},
    {"Council", "object"} => %{code: 4, name: "object", identity: @identity, proposal: 300},
    {"AccountKeys", "register"} => %{code: 1, name: "register", scheme: 0x10, policy: "optional"},
    {"AccountKeys", "registerSmall"} => %{code: 1, name: "register", scheme: 0x20, policy: "required"},
    {"AccountKeys", "rotate"} => %{code: 2, name: "rotate", scheme: 0x20},
    {"AccountKeys", "setPolicy"} => %{code: 3, name: "setPolicy", policy: "required"},
    {"AccountKeys", "clear"} => %{code: 4, name: "clear"},
    {"BinaryRegistry", "approve"} => %{code: 1, name: "approve", identity: @signer, binary: @binary, version: 2000},
    {"BinaryRegistry", "require"} => %{code: 2, name: "require", identity: @signer, version: 2001},
    {"BinaryRegistry", "attest"} => %{code: 3, name: "attest", identity: @identity, binary: @binary}
  }

  @none %{
    identity: nil,
    proposal: nil,
    kind: nil,
    choice: nil,
    scheme: nil,
    policy: nil,
    binary: nil,
    version: nil
  }

  defp vectors, do: @vectors |> File.read!() |> Jason.decode!()

  defp decode(address, hex) do
    {:ok, address_hash} = Hash.Address.cast(address)
    {:ok, data} = Data.cast(hex)
    SystemCall.decode(address_hash, data)
  end

  test "every request the node encodes is named, with its fields" do
    vectors = vectors()

    assert vectors |> Enum.map(&{&1["contract"], &1["case"]}) |> MapSet.new() ==
             @expected |> Map.keys() |> MapSet.new()

    for %{"contract" => contract, "case" => name, "input" => input} <- vectors do
      expected = @none |> Map.merge(%{contract: contract}) |> Map.merge(@expected[{contract, name}])
      assert decode(@addresses[contract], input) == expected, "#{contract} #{name}"
    end
  end

  test "the same input to another address names nothing" do
    [%{"input" => deposit} | _] = vectors()

    assert decode("0x0000000000000000000000000000000000000109", deposit) == nil
    assert decode("0x00000000000000000000000000000000000000ff", deposit) == nil
    {:ok, data} = Data.cast(deposit)
    assert SystemCall.decode(nil, data) == nil
  end

  test "an input that is no list starting with an operation number names nothing" do
    council = @addresses["Council"]

    # empty, a single byte, a string
    assert decode(council, "0x") == nil
    assert decode(council, "0x12") == nil
    assert decode(council, "0x83010203") == nil
    # an empty list, a list that starts with a list
    assert decode(council, "0xc0") == nil
    assert decode(council, "0xc3c20102") == nil
    # a number with a leading zero, a number wider than 64 bits
    assert decode(council, "0xc3820002") == nil
    assert decode(council, "0xca89010203040506070809") == nil
    # a list cut short, and bytes after the list
    assert decode(council, "0xc504808080") == nil
    assert decode(council, "0xc5048080808000") == nil
    # an ABI call
    assert decode(council, "0xa9059cbb000000000000000000000000000000000000000000000000000000000000000a") == nil
  end

  test "a field of the wrong size is left out, the operation still named" do
    # a bond operation whose identity is 31 bytes long
    input = "0xe304" <> "9f" <> String.duplicate("11", 31) <> "80" <> "80"
    assert %{name: "withdraw", identity: nil} = decode(@addresses["ValidatorBond"], input)
  end
end
