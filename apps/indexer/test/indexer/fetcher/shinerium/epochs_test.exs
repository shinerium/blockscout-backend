# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Indexer.Fetcher.Shinerium.EpochsTest do
  use Explorer.DataCase
  use Utils.CompileTimeEnvHelper, chain_type: [:explorer, :chain_type]

  import Mox

  setup :verify_on_exit!
  setup :set_mox_global

  # The tables are Explorer.Repo.Shinerium's, migrated with the chain type only.
  if @chain_type == :shinerium do
    alias Explorer.Chain.{Hash, Wei}
    alias Explorer.Chain.Shinerium.{Consensus, Epoch, EpochMember, Validator}
    alias Indexer.Fetcher.Shinerium.Epochs

    @args [transport: EthereumJSONRPC.Mox, transport_options: [], variant: EthereumJSONRPC.Geth]

    # Two members of the 0.2.0 network's committee, as shn_committeeMembers gives them.
    @alice %{
      "coinbase" => "0x0B5f7268A8081E9B871C902B3Bd968443B3fa173",
      "edAddress" => "0x62aDbfEA805C0Baf48B88A9e8C011dAE7e450765",
      "edPublic" => "7a8c7e56b6d2741a685511134b3e7e44c7a044784566e2c84e91816a730ea791",
      "blsPublic" => "8f0f6e6677..",
      "pqKeyHash" => "f985fb7c937d6d126f35ab9a07e2bb848ab90aa8760e1ee66cfe3640d383f3b1",
      "location" => %{"country" => "CA", "region" => "Quebec", "asn" => 16_276, "source" => "declared"}
    }

    @bob %{
      "coinbase" => "0x4fcb8D3bd2897a36C648171a0Ea3C6D93701b884",
      "edAddress" => "0x9434c7b49E217ba9a65c427b8dE9cFF2C77FDe80",
      "edPublic" => "ccc31774059cb9bb8b667e3693d31052f555e6328b18f73c79ac862b78530a18",
      "blsPublic" => "a7f43add81..",
      "pqKeyHash" => "815ddb7cb222534a30c60a22f7af16af1a8e8434ed48cb9adfbd3a7a22c57494",
      "location" => %{"country" => "SG", "asn" => 16_276, "source" => "declared"}
    }

    # A node that joins at the end of epoch 1.
    @carol %{
      "coinbase" => "0x936B096aeDa0DB3195Df7d3c4D6585098E5643E1",
      "edAddress" => "0xFc74Dc5766Df64F5A9Ab70Cb8Fd6bFC51bAf9368",
      "edPublic" => "9b4aaa715ee4937d00c421147e3d88b5689729af989282d2dce8716789315e5a",
      "blsPublic" => "8b18d9606f..",
      "location" => %{"country" => "GB", "region" => "England", "asn" => 63_473, "agreement" => 4}
    }

    # What a node of the tree 0.2.1-2da5803b adds to each record: the ending
    # committee's correlated misses and the slow epochs of the committee it
    # seats. Control block 3's `correlated` has another length than the
    # committee it counts, and its `slow` is null.
    @record_fields %{
      1 => %{"correlated" => [0, 1], "slow" => [0, 1]},
      2 => %{"correlated" => [0, 3], "slow" => [1, 0]},
      3 => %{"correlated" => [0], "slow" => nil}
    }

    defp control_block(number, served) do
      fields = if number in served, do: Map.get(@record_fields, number, %{}), else: %{}

      case control_block(number) do
        %{"epoch" => record} = control -> %{control | "epoch" => Map.merge(record, fields)}
        control -> control
      end
    end

    defp control_block(0) do
      %{
        "number" => "0x0",
        "hash" => hash(0),
        "committeeHash" => hash(100),
        "timestamp" => 1_793_806_200,
        "previousTxBlockNumber" => 0,
        "blockType" => 1
      }
    end

    defp control_block(1) do
      control_block(1, 11, %{
        "qcs" => 6,
        "signed" => [6, 5],
        "first" => 1,
        "removed" => [],
        "joined" => [],
        "missedBy" => [0, 0],
        "absentKept" => 0
      })
    end

    defp control_block(2) do
      control_block(2, 21, %{
        "qcs" => 4,
        "signed" => [4, 1],
        "first" => 0,
        "removed" => [%{"index" => 1, "reason" => 2}],
        "joined" => [@carol],
        "missedBy" => [0, 0],
        "absentKept" => 0
      })
    end

    defp control_block(3) do
      control_block(3, 31, %{
        "qcs" => 5,
        "signed" => [5, 5],
        "first" => 1,
        "removed" => [],
        "joined" => [],
        "missedBy" => [0, 0],
        "absentKept" => 0
      })
    end

    defp control_block(number, previous, record) do
      %{
        "number" => "0x#{number}",
        "hash" => hash(number),
        "committeeHash" => hash(100 + number),
        "timestamp" => 1_793_806_200 + number * 600,
        "previousTxBlockNumber" => previous,
        "blockType" => 3,
        "epoch" => record
      }
    end

    defp committee(number) when number in [0, 1], do: [@alice, @bob]
    defp committee(_number), do: [@alice, @carol]

    defp hash(n), do: "0x" <> String.pad_leading(Integer.to_string(n, 16), 64, "0")

    defp bond(%{"edPublic" => ed_public, "edAddress" => ed_address}, name) do
      %{
        "identity" => "0x" <> ed_public,
        "edAddress" => ed_address,
        "name" => name,
        "names" => "0x1",
        "status" => "active",
        "genesis" => true,
        "amount" => "0x152d02c7e14af6800000",
        "bondOwner" => "0xb67A9585b0D8B6d3B1b8E7E5a2A9D6f1C3e4B5a6",
        "refundAddress" => "0xb67A9585b0D8B6d3B1b8E7E5a2A9D6f1C3e4B5a6",
        "blsHash" => hash(7),
        "pqHash" => hash(8),
        "activeAt" => "0x0",
        "exiting" => false,
        "releaseAt" => "0x0",
        "forcedExit" => false,
        "required" => "0x152d02c7e14af6800000",
        "shortfall" => "0x0",
        "penaltyBox" => %{
          "seatFrom" => "0x5",
          "since" => "0x3",
          "strikes" => "0x1",
          "reason" => "0x2",
          "reasonName" => "absent",
          "active" => true,
          "epochsLeft" => "0x1"
        },
        "epoch" => "0x3",
        "blockNumber" => "0x2a",
        "blockHash" => hash(42),
        "time" => "0x6aebe5a0"
      }
    end

    # The node as far as `latest`, its control blocks and committees; alice's bond
    # is read, the others' are not (a node before R5 answers no bond at all). The
    # records of the control blocks in `served` have `correlated` and `slow`.
    defp node(latest, test_pid, served \\ []) do
      stub(EthereumJSONRPC.Mox, :json_rpc, fn
        %{id: id, method: "shn_controlBlockNumber"}, _ ->
          send(test_pid, {:latest, id})
          {:ok, "0x#{latest}"}

        requests, _ when is_list(requests) ->
          send(test_pid, {:batch, Enum.map(requests, &{&1.method, &1.params})})
          {:ok, Enum.map(requests, &answer(&1, served))}
      end)
    end

    defp answer(%{id: id, method: "shn_getControlBlockByNumber", params: ["0x" <> n]}, served),
      do: %{id: id, result: control_block(String.to_integer(n, 16), served)}

    defp answer(%{id: id, method: "shn_committeeMembers", params: ["0x" <> n]}, _served),
      do: %{id: id, result: committee(String.to_integer(n, 16))}

    defp answer(%{id: id, method: "shn_getValidator", params: ["0x" <> ed_public, "latest"]}, _served) do
      if ed_public == @alice["edPublic"],
        do: %{id: id, result: bond(@alice, "SCM01")},
        else: %{id: id, error: %{code: -32_601, message: "the method shn_getValidator does not exist"}}
    end

    defp full_hash(hex), do: hex |> Hash.Full.cast() |> elem(1)

    defp member_fields(epoch) do
      Repo.all(
        from(m in EpochMember,
          where: m.epoch_number == ^epoch,
          order_by: m.index,
          select: {m.signed, m.correlated, m.slow}
        )
      )
    end

    defp complete(epoch), do: Repo.get!(Epoch, epoch).record_complete

    test "stores the ended epochs and the running one, their committees, and the validators' bonds" do
      node(2, self())
      assert Epochs.update(%{json_rpc_named_arguments: @args}) == :ok

      assert_received {:batch, epoch_requests}

      assert epoch_requests ==
               Enum.map(0..2, &{"shn_getControlBlockByNumber", ["0x#{&1}"]}) ++
                 Enum.map(0..2, &{"shn_committeeMembers", ["0x#{&1}"]})

      assert [genesis, one, running] = Repo.all(from(e in Epoch, order_by: e.number))

      # epoch 0: the genesis's control block has no carrier; control block 1 ends it
      assert %Epoch{number: 0, carrier_block_number: nil, end_block_number: 12, qcs: 6, next_first: 1} = genesis
      assert genesis.started_at == ~U[2026-11-04 15:30:00.000000Z]
      assert genesis.ended_at == ~U[2026-11-04 15:40:00.000000Z]
      assert to_string(genesis.control_block_hash) == hash(0)
      assert Epoch.first_block_number(genesis) == 1

      # epoch 1: control block 2 says bob left as offline and carol joins
      assert %Epoch{number: 1, carrier_block_number: 12, end_block_number: 22, qcs: 4} = one
      assert Epoch.first_block_number(one) == 13
      assert [%{"edPublic" => carol_key, "edAddress" => _, "coinbase" => _, "location" => _}] = one.joined
      assert carol_key == @carol["edPublic"]

      # epoch 2 runs: what control block 3 would say is not known yet
      assert %Epoch{number: 2, carrier_block_number: 22, ended_at: nil, end_block_number: nil, qcs: nil} = running
      assert running.joined == nil

      members = Repo.all(from(m in EpochMember, where: m.epoch_number == 1, order_by: m.index))
      assert Enum.map(members, &{&1.index, &1.signed, &1.removal_reason}) == [{0, 4, nil}, {1, 1, 2}]
      assert to_string(hd(members).identity) == "0x" <> @alice["edPublic"]
      assert to_string(hd(members).ed_address_hash) == String.downcase(@alice["edAddress"])
      assert to_string(hd(members).pq_key_hash) == "0x" <> @alice["pqKeyHash"]
      assert hd(members).location["region"] == "Quebec"

      assert Repo.all(from(m in EpochMember, where: m.epoch_number == 2, select: m.signed)) == [nil, nil]

      # every identity of a committee or among the joining nodes; only alice's bond was read
      assert_received {:batch, validator_requests}
      assert length(validator_requests) == 3
      assert Enum.all?(validator_requests, &match?({"shn_getValidator", [_, "latest"]}, &1))

      validators = Repo.all(from(v in Validator, order_by: v.identity))
      assert length(validators) == 3

      alice = Repo.get!(Validator, full_hash("0x" <> @alice["edPublic"]))
      assert %Validator{name: "SCM01", status: "active", genesis: true, active_at: 0, release_at: nil} = alice
      assert alice.amount == %Wei{value: Decimal.new(100_000_000_000_000_000_000_000)}
      assert alice.shortfall == %Wei{value: Decimal.new(0)}
      assert alice.bond_block_number == 42
      assert alice.penalty == nil

      assert alice.penalty_box == %{
               "seat_from" => 5,
               "since" => 3,
               "strikes" => 1,
               "reason" => 2,
               "reason_name" => "absent",
               "active" => true,
               "epochs_left" => 1
             }

      bob = Repo.get!(Validator, full_hash("0x" <> @bob["edPublic"]))
      assert %Validator{name: nil, status: nil, bond_block_number: nil} = bob
    end

    test "a later round asks only from the first epoch not ended, and ends the running one" do
      node(2, self())
      Epochs.update(%{json_rpc_named_arguments: @args})
      assert Consensus.last_ended_epoch() == 1

      node(3, self())
      flush()
      Epochs.update(%{json_rpc_named_arguments: @args})

      assert_received {:batch, epoch_requests}

      assert epoch_requests == [
               {"shn_getControlBlockByNumber", ["0x2"]},
               {"shn_getControlBlockByNumber", ["0x3"]},
               {"shn_committeeMembers", ["0x2"]},
               {"shn_committeeMembers", ["0x3"]}
             ]

      assert Consensus.last_ended_epoch() == 2
      assert %Epoch{end_block_number: 32, qcs: 5} = Repo.get!(Epoch, 2)
      assert Repo.all(from(m in EpochMember, where: m.epoch_number == 2, order_by: m.index, select: m.signed)) == [5, 5]

      # alice's bond was read last round, so bob's and carol's come first
      assert_received {:batch, [{"shn_getValidator", [first, _]} | _]}
      refute first == "0x" <> @alice["edPublic"]
    end

    test "a node that serves the record's correlated and slow: each member's, from the records that end and seat it" do
      node(2, self(), 0..3)
      Epochs.update(%{json_rpc_named_arguments: @args})

      # control block 1 ends epoch 0; the genesis's control block has no record
      assert member_fields(0) == [{6, 0, nil}, {5, 1, nil}]
      # control block 2 ends epoch 1, and control block 1 seated its committee
      assert member_fields(1) == [{4, 0, 0}, {1, 3, 1}]
      # epoch 2 runs: control block 2 seated its committee
      assert member_fields(2) == [{nil, nil, 1}, {nil, nil, 0}]
      assert Enum.map(0..2, &complete/1) == [true, true, false]

      node(3, self(), 0..3)
      Epochs.update(%{json_rpc_named_arguments: @args})

      # control block 3's `correlated` counts another committee, and its `slow` is null
      assert member_fields(2) == [{5, nil, 1}, {5, nil, 0}]
      assert member_fields(3) == [{nil, nil, nil}, {nil, nil, nil}]
      assert complete(2)
    end

    test "the ended epochs read from a node without them are read again once it serves them" do
      node(2, self())
      Epochs.update(%{json_rpc_named_arguments: @args})
      assert member_fields(1) == [{4, nil, nil}, {1, nil, nil}]
      assert Enum.map(0..2, &complete/1) == [false, false, false]

      # the node still serves neither: nothing is read again
      flush()
      Epochs.update(%{json_rpc_named_arguments: @args})
      assert_received {:batch, [{"shn_getControlBlockByNumber", ["0x2"]}, {"shn_committeeMembers", ["0x2"]}]}
      assert_received {:batch, [{"shn_getValidator", _} | _]}
      refute_received {:batch, _}

      # updated: epoch 2 ends with them, and then epochs 0 and 1 are read again
      node(3, self(), 0..3)
      flush()
      Epochs.update(%{json_rpc_named_arguments: @args})
      assert_received {:batch, [{"shn_getControlBlockByNumber", ["0x2"]} | _]}
      assert_received {:batch, again}

      assert again ==
               Enum.map(0..2, &{"shn_getControlBlockByNumber", ["0x#{&1}"]}) ++
                 Enum.map(0..1, &{"shn_committeeMembers", ["0x#{&1}"]})

      assert member_fields(0) == [{6, 0, nil}, {5, 1, nil}]
      assert member_fields(1) == [{4, 0, 0}, {1, 3, 1}]
      assert Enum.map(0..2, &complete/1) == [true, true, true]
      assert Consensus.incomplete_epochs(10) == []
    end

    test "an epoch whose record still lacks them is not written again, and stays ended" do
      node(2, self())
      Epochs.update(%{json_rpc_named_arguments: @args})

      # control block 1, which ends epoch 0, still comes without them
      node(3, self(), 2..3)
      Epochs.update(%{json_rpc_named_arguments: @args})

      assert %Epoch{record_complete: false, qcs: 6, end_block_number: 12} = Repo.get!(Epoch, 0)
      assert member_fields(0) == [{6, nil, nil}, {5, nil, nil}]
      assert complete(1)
      assert Consensus.last_ended_epoch() == 2
      assert Consensus.incomplete_epochs(10) == [0]

      # the next round asks again for epoch 0 alone
      flush()
      Epochs.update(%{json_rpc_named_arguments: @args})
      assert_received {:batch, [{"shn_getControlBlockByNumber", ["0x3"]} | _]}
      assert_received {:batch, again}

      assert again == [
               {"shn_getControlBlockByNumber", ["0x0"]},
               {"shn_getControlBlockByNumber", ["0x1"]},
               {"shn_committeeMembers", ["0x0"]}
             ]
    end

    test "a node that answers no epoch stores nothing" do
      stub(EthereumJSONRPC.Mox, :json_rpc, fn
        %{method: "shn_controlBlockNumber"}, _ -> {:error, %{code: -32_601, message: "the method does not exist"}}
        requests, _ when is_list(requests) -> {:ok, []}
      end)

      assert Epochs.update(%{json_rpc_named_arguments: @args}) == :ok
      assert Repo.aggregate(Epoch, :count) == 0
    end

    defp flush do
      receive do
        _ -> flush()
      after
        0 -> :ok
      end
    end
  end
end
