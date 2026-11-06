# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule EthereumJSONRPC.ShineriumTest do
  use ExUnit.Case, async: true
  use Utils.CompileTimeEnvHelper, chain_type: [:explorer, :chain_type]

  alias EthereumJSONRPC.{Blocks, Transaction}

  if @chain_type == :shinerium do
    # Block 21 of the 0.2.0 network (4 November 2026), a carrier, as the node
    # serves it, with two of its nine withdrawals.
    @carrier %{
      "anchorChainHash" => "0x0000000000000000000000000000000000000000000000000000000000000000",
      "baseFeePerGas" => "0x3b9aca00",
      "blobGasUsed" => "0x0",
      "blockAccessListHash" => "0x811b48da6e1d32fa145494b5980d7cba1eb49a7ae4fa473a67760ce547bb81fc",
      "blockType" => "control",
      "controlBlockHash" => "0x8108c2bbd5b2660c5a38d58fc8150cb41f3106679ffba149bdf7c09d6a2439d0",
      "controlBlockNumber" => "0x5",
      "difficulty" => "0x20000",
      "excessBlobGas" => "0x0",
      "extraData" => "0x",
      "gasLimit" => "0x11e1a300",
      "gasUsed" => "0x0",
      "hash" => "0x507a19b8a0396162d2fd38b9ade60af5b5c798d6fac0a66168c3d32985f8612e",
      "logsBloom" => "0x" <> String.duplicate("0", 512),
      "miner" => "0x9cc7710deb226f2a0fe4780bbf08818f74eb7420",
      "mixHash" => "0x0000000000000000000000000000000000000000000000000000000000000000",
      "nonce" => "0x0000000000000000",
      "number" => "0x15",
      "parentHash" => "0xe4fd62fccd68d949a8f11417b2eecf801c140fc28128c38a78d1893652da4e8d",
      "poqMiner" => "0x0000000000000000000000000000000000000000",
      "receiptsRoot" => "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421",
      "reward" => "0x5c693c26892b87527",
      "sha3Uncles" => "0x1dcc4de8dec75d7aab85b567b6ccd41ad312451b948a7413f0a142fd40d49347",
      "size" => "0x422",
      "stateRoot" => "0xddff3fdcbadfb5275dddc12919f6e56f129d8858548554693609b97351336773",
      "timestamp" => "0x6aeb61c6",
      "totalDifficulty" => "0x2a0400",
      "totalSupply" => "0xa56fdb351351ba24ca69f5",
      "transactions" => [],
      "transactionsRoot" => "0x56e81f171bcc55a6ff8345e692c0f86e5b48e01b996cadc001622fb5e363b421",
      "txCount" => 0,
      "uncles" => [],
      "withdrawalBaseIndex" => 45,
      "withdrawals" => [
        %{
          "index" => "0x24",
          "address" => "0x9cc7710deb226f2a0fe4780bbf08818f74eb7420",
          "amount" => "0x7cbda4f9c",
          "rewardType" => "committee",
          "validatorIndex" => "0x4",
          "validator" => "0xfc74dc5766df64f5a9ab70cb8fd6bfc51baf9368"
        },
        %{
          "index" => "0x2c",
          "address" => "0x0000000000000000000000000000000000000105",
          "amount" => "0x7166ea7c5",
          "rewardType" => "support",
          "validatorIndex" => "0x4",
          "validator" => "0xfc74dc5766df64f5a9ab70cb8fd6bfc51baf9368"
        }
      ],
      "withdrawalsRoot" => "0xab0cf53b0f35f052648193150a81bb93181220efc1cb69c2955cb2442bffbf16"
    }

    # A hybrid transaction (version 1 with an FN-DSA-512 witness), as the node's
    # RPCTransaction gives it.
    @hybrid %{
      "accessList" => [],
      "blockHash" => "0x507a19b8a0396162d2fd38b9ade60af5b5c798d6fac0a66168c3d32985f8612e",
      "blockNumber" => "0x15",
      "chainId" => "0x139b",
      "from" => "0x2b2a63c920f8b7a3f1c1b2e5d6a0e8c3f4a5b6c7",
      "gas" => "0x94ed",
      "gasPrice" => "0x3b9aca00",
      "hash" => "0xe0cc04341b5a0a5c0d28f3c8b9e9d1a7c2f4e6b8a0c2e4f6a8b0c2d4e6f8a0b2",
      "input" => "0x",
      "maxFeePerGas" => "0x77359400",
      "maxPriorityFeePerGas" => "0x0",
      "nonce" => "0x3",
      "pqWitness" => %{"scheme" => "0x20", "signature" => "0x" <> String.duplicate("ab", 666)},
      "r" => "0x1b",
      "s" => "0x2c",
      "shnForm" => "hybrid",
      "shnMetadataHash" => "0x9a3ff8a3c7a1b15c3c0b2a8f6f7e8d9c0b1a2f3e4d5c6b7a8f9e0d1c2b3a4f5e",
      "to" => "0x0000000000000000000000000000000000000111",
      "transactionIndex" => "0x0",
      "type" => "0x2",
      "v" => "0x1",
      "value" => "0xde0b6b3a7640000",
      "version" => 1,
      "yParity" => "0x1"
    }

    describe "blocks" do
      test "take the header's Shinerium fields" do
        %Blocks{blocks_params: [params]} =
          Blocks.from_responses([%{id: 0, result: @carrier}], %{0 => %{number: 21}})

        assert params.shn_block_type == "control"
        assert params.shn_control_block_number == 5
        assert params.shn_control_block_hash == "0x8108c2bbd5b2660c5a38d58fc8150cb41f3106679ffba149bdf7c09d6a2439d0"
        assert params.shn_reward == 106_542_714_564_027_905_319
        assert params.shn_total_supply == 200_000_986_577_454_855_327_738_357
        assert params.shn_block_access_list_hash == "0x811b48da6e1d32fa145494b5980d7cba1eb49a7ae4fa473a67760ce547bb81fc"
        assert params.shn_poq_miner_hash == "0x0000000000000000000000000000000000000000"
        assert params.shn_anchor_chain_hash == "0x0000000000000000000000000000000000000000000000000000000000000000"
        assert params.number == 21
      end

      # The BLS certificate of the node's smartfhs.QC.Encode() (0.2.0-39ebea86):
      # epoch 287, view 4106, signers 0x6f, a signature of 96 bytes.
      @justify "0xf88b82011f82100aa03d0514715ed027b78d0cb6cb4a56a3e20bc34950130b2be93b36310f3a13f38a6f01b860" <>
                 String.duplicate("ab", 96)

      test "take the consensus of a node with R4: epoch, view and the parent's certificate" do
        block = Map.merge(@carrier, %{"epoch" => "0x4", "view" => "0x1d", "justify" => @justify})
        %Blocks{blocks_params: [params]} = Blocks.from_responses([%{id: 0, result: block}], %{0 => %{number: 21}})

        assert params.shn_epoch == 4
        assert params.shn_view == 29
        assert params.shn_justify_epoch == 287
        assert params.shn_justify_view == 4106
        assert params.shn_justify_scheme == 1
        assert params.shn_justify_signers == [0, 1, 2, 3, 5, 6]
      end

      test "leave out a certificate the explorer cannot read" do
        block = Map.merge(@carrier, %{"epoch" => "0x4", "view" => "0x1d", "justify" => "0xc0"})
        %Blocks{blocks_params: [params]} = Blocks.from_responses([%{id: 0, result: block}], %{0 => %{number: 21}})

        assert {params.shn_epoch, params.shn_view} == {4, 29}
        refute Map.has_key?(params, :shn_justify_signers)
        refute Map.has_key?(params, :shn_justify_view)
      end

      test "of another node have none of them" do
        other = Map.drop(@carrier, ~w(blockType controlBlockNumber controlBlockHash reward totalSupply
                                      blockAccessListHash poqMiner anchorChainHash))

        %Blocks{blocks_params: [params]} = Blocks.from_responses([%{id: 0, result: other}], %{0 => %{number: 21}})

        assert params |> Map.keys() |> Enum.filter(&String.starts_with?(Atom.to_string(&1), "shn_")) == []
      end
    end

    describe "withdrawals" do
      test "take the reward's type and the member's identity" do
        %Blocks{withdrawals_params: withdrawals} =
          Blocks.from_responses([%{id: 0, result: @carrier}], %{0 => %{number: 21}})

        assert [committee, support] = Enum.sort_by(withdrawals, & &1.index)
        assert committee.index == 36
        assert committee.validator_index == 4
        assert committee.amount == 0x7CBDA4F9C * 1_000_000_000
        assert committee.shn_reward_type == "committee"
        assert committee.shn_validator_hash == "0xfc74dc5766df64f5a9ab70cb8fd6bfc51baf9368"
        assert support.shn_reward_type == "support"
        assert support.address_hash == "0x0000000000000000000000000000000000000105"
      end
    end

    describe "transactions" do
      test "take the form, the witness's scheme and the metadata hash" do
        params = @hybrid |> Transaction.to_elixir() |> Transaction.elixir_to_params()

        assert params.shn_version == 1
        assert params.shn_form == "hybrid"
        assert params.shn_pq_scheme == 0x20
        assert params.shn_metadata_hash == "0x9a3ff8a3c7a1b15c3c0b2a8f6f7e8d9c0b1a2f3e4d5c6b7a8f9e0d1c2b3a4f5e"
        refute Map.has_key?(params, :shn_pq_sender_hash)
        # the witness's signature is not kept
        refute params |> inspect() |> String.contains?(String.duplicate("ab", 666))
      end

      test "of Ethereum's forms have version 0 and no form" do
        ethereum =
          @hybrid
          |> Map.drop(~w(pqWitness shnForm shnMetadataHash))
          |> Map.put("version", 0)

        params = ethereum |> Transaction.to_elixir() |> Transaction.elixir_to_params()

        assert params.shn_version == 0
        refute Map.has_key?(params, :shn_form)
        refute Map.has_key?(params, :shn_pq_scheme)
      end

      test "take a post-quantum sender and a version sent as a quantity" do
        params =
          @hybrid
          |> Map.merge(%{"version" => "0x1", "pqSender" => "0x0a66608083f3b2c1d0e9f8a7b6c5d4e3f2a1b0c9"})
          |> Transaction.to_elixir()
          |> Transaction.elixir_to_params()

        assert params.shn_version == 1
        assert params.shn_pq_sender_hash == "0x0a66608083f3b2c1d0e9f8a7b6c5d4e3f2a1b0c9"
      end
    end
  end
end
