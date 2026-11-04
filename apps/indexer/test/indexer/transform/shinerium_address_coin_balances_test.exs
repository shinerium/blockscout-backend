# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Indexer.Transform.ShineriumAddressCoinBalancesTest do
  use ExUnit.Case, async: true
  use Utils.CompileTimeEnvHelper, chain_type: [:explorer, :chain_type]

  alias Indexer.Transform.AddressCoinBalances

  if @chain_type == :shinerium do
    @bond "0x0000000000000000000000000000000000000102"
    @council "0x0000000000000000000000000000000000000107"
    @vesting "0x0000000000000000000000000000000000000108"
    @claim "0x0000000000000000000000000000000000000109"
    @identity "0x00000000000000000000000000000000000000000000000000000000000000aa"
    @account "0x000000000000000000000000a7c207bd683e0000000000000000000000000001"
    @recipient "0x0000000000000000000000002b2a63c920f8b7a3f1c1b2e5d6a0e8c3f4a5b6c7"
    @pool "0x000000000000000000000000a57a71d381a20000000000000000000000000002"

    test "the system events' topics are their signatures' hashes" do
      signatures = %{
        bond_withdrawn: "BondWithdrawn(bytes32,address,uint256)",
        airdrop_claimed: "AirdropClaimed(address,address,uint256)",
        vesting_granted: "VestingGranted(address,address,uint256)",
        proposal_executed: "ProposalExecuted(uint64,uint8,uint64,bytes32,uint256)"
      }

      for {event, topic} <- AddressCoinBalances.shinerium_system_event_topics() do
        assert topic == "0x" <> Base.encode16(ExKeccak.hash_256(signatures[event]), case: :lower)
      end
    end

    test "a relayed claim's recipient, not its account" do
      topics = AddressCoinBalances.shinerium_system_event_topics()

      assert addresses(log(@claim, topics.airdrop_claimed, [@account, @recipient])) ==
               MapSet.new([@claim, "0x2b2a63c920f8b7a3f1c1b2e5d6a0e8c3f4a5b6c7"])
    end

    test "a vesting grant's pool and recipient" do
      topics = AddressCoinBalances.shinerium_system_event_topics()

      assert addresses(log(@vesting, topics.vesting_granted, [@pool, @recipient])) ==
               MapSet.new([
                 @vesting,
                 "0xa57a71d381a20000000000000000000000000002",
                 "0x2b2a63c920f8b7a3f1c1b2e5d6a0e8c3f4a5b6c7"
               ])
    end

    test "a bond's withdrawal address" do
      topics = AddressCoinBalances.shinerium_system_event_topics()

      assert addresses(log(@bond, topics.bond_withdrawn, [@identity, @recipient])) ==
               MapSet.new([@bond, "0x2b2a63c920f8b7a3f1c1b2e5d6a0e8c3f4a5b6c7"])
    end

    test "a council transfer's treasury account and recipient" do
      topics = AddressCoinBalances.shinerium_system_event_topics()
      # kind 1, account 1 (0x…0111), the recipient as bytes32, an amount
      data =
        "0x" <>
          word(1) <> word(1) <> String.slice(@recipient, 2..-1//1) <> word(1_000_000_000_000_000_000)

      log = @council |> log(topics.proposal_executed, [word_topic(7)]) |> Map.put(:data, data)

      assert addresses(log) ==
               MapSet.new([
                 @council,
                 "0x0000000000000000000000000000000000000111",
                 "0x2b2a63c920f8b7a3f1c1b2e5d6a0e8c3f4a5b6c7"
               ])
    end

    test "a council decision with no address in its target names only the account" do
      topics = AddressCoinBalances.shinerium_system_event_topics()
      data = "0x" <> word(3) <> word(0) <> String.duplicate("ff", 32) <> word(0)
      log = @council |> log(topics.proposal_executed, [word_topic(8)]) |> Map.put(:data, data)

      assert addresses(log) == MapSet.new([@council, "0x0000000000000000000000000000000000000110"])
    end

    test "the same event from another contract, or another event, names nobody else" do
      topics = AddressCoinBalances.shinerium_system_event_topics()
      other = "0x00000000000000000000000000000000000000ff"

      assert addresses(log(other, topics.airdrop_claimed, [@account, @recipient])) == MapSet.new([other])

      assert addresses(log(@claim, "0x" <> String.duplicate("11", 32), [@account, @recipient])) ==
               MapSet.new([@claim])
    end

    test "a pending log names nobody" do
      topics = AddressCoinBalances.shinerium_system_event_topics()
      pending = @claim |> log(topics.airdrop_claimed, [@account, @recipient]) |> Map.put(:type, "pending")

      assert AddressCoinBalances.params_set(%{logs_params: [Map.put(pending, :block_number, nil)]}) == MapSet.new()
    end

    defp addresses(log) do
      %{logs_params: [log]}
      |> AddressCoinBalances.params_set()
      |> MapSet.new(fn %{address_hash: address_hash, block_number: 21} -> address_hash end)
    end

    defp log(address, first_topic, topics) do
      [second, third, fourth] = topics ++ List.duplicate(nil, 3 - length(topics))

      %{
        address_hash: address,
        block_number: 21,
        data: "0x",
        first_topic: first_topic,
        second_topic: second,
        third_topic: third,
        fourth_topic: fourth,
        index: 0,
        transaction_hash: "0xe0cc04341b5a0a5c0d28f3c8b9e9d1a7c2f4e6b8a0c2e4f6a8b0c2d4e6f8a0b2",
        type: "mined"
      }
    end

    defp word(integer), do: integer |> Integer.to_string(16) |> String.downcase() |> String.pad_leading(64, "0")
    defp word_topic(integer), do: "0x" <> word(integer)
  end
end
