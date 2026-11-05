# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Explorer.Chain.ShineriumTest do
  use Explorer.DataCase
  use Utils.CompileTimeEnvHelper, chain_type: [:explorer, :chain_type]

  if @chain_type == :shinerium do
    alias Explorer.Chain.Address.Name
    alias Explorer.Chain.{Block, Hash, Import, Transaction, Wei, Withdrawal}
    alias Explorer.Chain.Shinerium.AddressNames
    alias Explorer.Chain.Supply.Shinerium, as: Supply

    @block_hash "0x507a19b8a0396162d2fd38b9ade60af5b5c798d6fac0a66168c3d32985f8612e"
    @miner "0x9cc7710deb226f2a0fe4780bbf08818f74eb7420"
    @identity "0xfc74dc5766df64f5a9ab70cb8fd6bfc51baf9368"
    @sender "0x2b2a63c920f8b7a3f1c1b2e5d6a0e8c3f4a5b6c7"
    @treasury "0x0000000000000000000000000000000000000111"
    @transaction_hash "0xe0cc04341b5a0a5c0d28f3c8b9e9d1a7c2f4e6b8a0c2e4f6a8b0c2d4e6f8a0b2"
    @metadata_hash "0x9a3ff8a3c7a1b15c3c0b2a8f6f7e8d9c0b1a2f3e4d5c6b7a8f9e0d1c2b3a4f5e"
    @zero_address "0x0000000000000000000000000000000000000000"
    @zero_hash "0x0000000000000000000000000000000000000000000000000000000000000000"

    defp block_params(overrides) do
      Map.merge(
        %{
          consensus: true,
          difficulty: 0x20000,
          gas_limit: 300_000_000,
          gas_used: 21_000,
          hash: @block_hash,
          miner_hash: @miner,
          nonce: 0,
          number: 21,
          parent_hash: "0xe4fd62fccd68d949a8f11417b2eecf801c140fc28128c38a78d1893652da4e8d",
          size: 1058,
          timestamp: ~U[2026-11-04 16:48:06.000000Z],
          total_difficulty: 0x2A0400,
          base_fee_per_gas: 1_000_000_000,
          shn_block_type: "control",
          shn_control_block_number: 5,
          shn_control_block_hash: "0x8108c2bbd5b2660c5a38d58fc8150cb41f3106679ffba149bdf7c09d6a2439d0",
          shn_reward: 106_542_714_564_027_905_319,
          shn_total_supply: 200_000_986_577_454_855_327_738_357,
          shn_block_access_list_hash: "0x811b48da6e1d32fa145494b5980d7cba1eb49a7ae4fa473a67760ce547bb81fc",
          shn_poq_miner_hash: @zero_address,
          shn_anchor_chain_hash: @zero_hash
        },
        overrides
      )
    end

    defp import_carrier(block_overrides \\ %{}) do
      Import.all(%{
        addresses: %{params: [%{hash: @miner}, %{hash: @sender}, %{hash: @treasury}]},
        blocks: %{params: [block_params(block_overrides)]},
        transactions: %{
          params: [
            %{
              block_hash: @block_hash,
              block_number: 21,
              cumulative_gas_used: 21_000,
              from_address_hash: @sender,
              gas: 38_125,
              gas_price: 1_000_000_000,
              gas_used: 21_000,
              hash: @transaction_hash,
              index: 0,
              input: "0x",
              nonce: 3,
              r: 0x1B,
              s: 0x2C,
              status: :ok,
              to_address_hash: @treasury,
              type: 2,
              v: 1,
              value: 1_000_000_000_000_000_000,
              shn_version: 1,
              shn_form: "hybrid",
              shn_pq_scheme: 0x20,
              shn_metadata_hash: @metadata_hash
            }
          ]
        },
        withdrawals: %{
          params: [
            %{
              index: 36,
              validator_index: 4,
              amount: 33_484_853_148_000_000_000,
              address_hash: @miner,
              block_hash: @block_hash,
              shn_reward_type: "committee",
              shn_validator_hash: @identity
            }
          ]
        }
      })
    end

    describe "import" do
      test "keeps a carrier's Shinerium fields, its transaction's form and its rewards' types" do
        assert {:ok, _} = import_carrier()

        {:ok, block_hash} = Hash.Full.cast(@block_hash)
        block = Repo.get!(Block, block_hash)
        assert block.shn_block_type == "control"
        assert block.shn_control_block_number == 5

        assert to_string(block.shn_control_block_hash) ==
                 "0x8108c2bbd5b2660c5a38d58fc8150cb41f3106679ffba149bdf7c09d6a2439d0"

        assert block.shn_reward == %Wei{value: Decimal.new(106_542_714_564_027_905_319)}
        assert block.shn_total_supply == %Wei{value: Decimal.new(200_000_986_577_454_855_327_738_357)}
        assert to_string(block.shn_poq_miner_hash) == @zero_address

        {:ok, transaction_hash} = Hash.Full.cast(@transaction_hash)
        transaction = Repo.get!(Transaction, transaction_hash)
        assert transaction.shn_version == 1
        assert transaction.shn_form == "hybrid"
        assert transaction.shn_pq_scheme == 0x20
        assert to_string(transaction.shn_metadata_hash) == @metadata_hash
        assert transaction.shn_pq_sender_hash == nil

        assert [withdrawal] = Repo.all(Withdrawal)
        assert withdrawal.shn_reward_type == "committee"
        assert to_string(withdrawal.shn_validator_hash) == @identity
      end

      test "updates the fields when the block is fetched again" do
        assert {:ok, _} = import_carrier()
        assert {:ok, _} = import_carrier(%{shn_total_supply: 200_000_986_577_454_855_327_738_358, shn_reward: 1})

        {:ok, block_hash} = Hash.Full.cast(@block_hash)
        block = Repo.get!(Block, block_hash)
        assert block.shn_total_supply == %Wei{value: Decimal.new(200_000_986_577_454_855_327_738_358)}
        assert block.shn_reward == %Wei{value: Decimal.new(1)}
      end
    end

    describe "supply" do
      test "is the latest consensus block's total supply, in SHN" do
        insert(:block,
          number: 1,
          shn_total_supply: %Wei{value: Decimal.new(200_000_000) |> Decimal.mult(wei_per_coin())}
        )

        insert(:block,
          number: 2,
          shn_total_supply: %Wei{value: Decimal.new("200000986.577454855327738357") |> Decimal.mult(wei_per_coin())}
        )

        # a block no longer in the chain does not count
        insert(:block,
          number: 3,
          consensus: false,
          shn_total_supply: %Wei{value: Decimal.new(1) |> Decimal.mult(wei_per_coin())}
        )

        assert Decimal.equal?(Supply.total(), Decimal.new("200000986.577454855327738357"))
        assert Decimal.equal?(Supply.circulating(), Supply.total())
      end

      test "is unknown before a block carries it" do
        insert(:block, number: 1)
        assert Supply.total() == nil
      end

      test "is the chain's supply in the API" do
        insert(:block, number: 7, shn_total_supply: %Wei{value: Decimal.new(5) |> Decimal.mult(wei_per_coin())})
        assert Decimal.equal?(Explorer.Chain.total_supply(), Decimal.new(5))
      end
    end

    describe "address names" do
      setup do
        path = Path.join(System.tmp_dir!(), "shinerium-names-#{System.unique_integer([:positive])}.json")
        on_exit(fn -> File.rm(path) end)
        %{path: path}
      end

      test "name the accounts of the file", %{path: path} do
        File.write!(
          path,
          JSON.encode!([
            %{"address" => "0x0000000000000000000000000000000000000104", "name" => "Reward pot"},
            %{"address" => @treasury, "name" => " DAO treasury account 1: Developer Grants & Tooling "},
            %{"address" => "not an address", "name" => "skipped"},
            %{"address" => "0x0000000000000000000000000000000000000105", "name" => ""}
          ])
        )

        assert {:ok, 2} = AddressNames.import_file(path)

        assert primary_names() == %{
                 "0x0000000000000000000000000000000000000104" => "Reward pot",
                 @treasury => "DAO treasury account 1: Developer Grants & Tooling"
               }

        # again: nothing changes
        assert {:ok, 0} = AddressNames.import_file(path)
        assert Repo.aggregate(Name, :count) == 2
      end

      test "replace an account's primary name", %{path: path} do
        insert(:address, hash: @treasury)
        {:ok, treasury} = Hash.Address.cast(@treasury)
        {:ok, _} = Name.create_primary_address_name(Repo, "old name", treasury)

        File.write!(path, JSON.encode!([%{"address" => @treasury, "name" => "Treasury 1"}]))
        assert {:ok, 1} = AddressNames.import_file(path)

        assert primary_names() == %{@treasury => "Treasury 1"}
        assert Repo.get_by(Name, address_hash: treasury, name: "old name").primary == false
      end

      test "report a file that cannot be read", %{path: path} do
        assert {:error, :enoent} = AddressNames.import_file(path)
        File.write!(path, JSON.encode!(%{"address" => @treasury}))
        assert {:error, :not_a_list} = AddressNames.import_file(path)
      end
    end

    defp wei_per_coin, do: Decimal.new(1_000_000_000_000_000_000)

    defp primary_names do
      Name
      |> Repo.all()
      |> Enum.filter(& &1.primary)
      |> Map.new(&{to_string(&1.address_hash), &1.name})
    end
  end
end
