# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule BlockScoutWeb.API.V2.ShineriumTest do
  # The responses are checked against the OpenAPI schema by `json_response/2`.
  use BlockScoutWeb.ConnCase
  use Utils.CompileTimeEnvHelper, chain_type: [:explorer, :chain_type]

  if @chain_type == :shinerium do
    import Mox

    alias Explorer.Chain.{Data, Hash, Wei}

    @control_block_hash "0x8108c2bbd5b2660c5a38d58fc8150cb41f3106679ffba149bdf7c09d6a2439d0"
    @access_list_hash "0x811b48da6e1d32fa145494b5980d7cba1eb49a7ae4fa473a67760ce547bb81fc"
    @identity "0xfc74dc5766df64f5a9ab70cb8fd6bfc51baf9368"
    @metadata_hash "0x9a3ff8a3c7a1b15c3c0b2a8f6f7e8d9c0b1a2f3e4d5c6b7a8f9e0d1c2b3a4f5e"

    defp full_hash(string), do: string |> Hash.Full.cast() |> elem(1)
    defp address_hash(string), do: string |> Hash.Address.cast() |> elem(1)

    defp carrier do
      insert(:block,
        shn_block_type: "control",
        shn_control_block_number: 5,
        shn_control_block_hash: full_hash(@control_block_hash),
        shn_reward: %Wei{value: Decimal.new(106_542_714_564_027_905_319)},
        shn_total_supply: %Wei{value: Decimal.new(200_000_986_577_454_855_327_738_357)},
        shn_block_access_list_hash: full_hash(@access_list_hash),
        shn_poq_miner_hash: address_hash("0x0000000000000000000000000000000000000000"),
        shn_anchor_chain_hash: full_hash("0x" <> String.duplicate("0", 64))
      )
    end

    @carrier_json %{
      "block_type" => "control",
      "control_block_number" => 5,
      "control_block_hash" => @control_block_hash,
      "reward" => "106542714564027905319",
      "total_supply" => "200000986577454855327738357",
      "block_access_list_hash" => @access_list_hash,
      "poq_miner_hash" => nil,
      "anchor_chain_hash" => nil,
      "epoch" => nil,
      "view" => nil,
      "justify" => nil
    }

    describe "blocks" do
      test "a carrier's Shinerium fields, the zero miner and anchor as null", %{conn: conn} do
        block = carrier()

        response = conn |> get("/api/v2/blocks/#{block.hash}") |> json_response(200)
        assert response["shinerium"] == @carrier_json

        response = conn |> get("/api/v2/blocks/#{block.number}") |> json_response(200)
        assert response["shinerium"] == @carrier_json
      end

      test "in the list too, to mark the carriers", %{conn: conn} do
        carrier()
        insert(:block, shn_block_type: "normal", shn_reward: %Wei{value: Decimal.new(0)})

        response = conn |> get("/api/v2/blocks") |> json_response(200)

        assert response["items"] |> Enum.map(& &1["shinerium"]["block_type"]) |> Enum.sort() == ["control", "normal"]
      end

      test "a block indexed before the chain type: every field null", %{conn: conn} do
        block = insert(:block)

        response = conn |> get("/api/v2/blocks/#{block.hash}") |> json_response(200)
        assert response["shinerium"] |> Map.values() |> Enum.uniq() == [nil]
      end
    end

    describe "withdrawals" do
      test "the reward's type and the member's identity", %{conn: conn} do
        block = carrier()

        withdrawal =
          insert(:withdrawal,
            block: block,
            block_hash: block.hash,
            shn_reward_type: "committee",
            shn_validator_hash: address_hash(@identity)
          )

        insert(:withdrawal, block: block, block_hash: block.hash, shn_reward_type: "support")

        expected = %{"reward_type" => "committee", "validator_hash" => @identity}

        for path <- [
              "/api/v2/withdrawals",
              "/api/v2/blocks/#{block.hash}/withdrawals",
              "/api/v2/addresses/#{withdrawal.address_hash}/withdrawals"
            ] do
          response = conn |> get(path) |> json_response(200)
          item = Enum.find(response["items"], &(&1["index"] == withdrawal.index))
          assert item["shinerium"] == expected, path
        end

        response = conn |> get("/api/v2/withdrawals") |> json_response(200)

        assert response["items"] |> Enum.map(& &1["shinerium"]["reward_type"]) |> Enum.sort() == [
                 "committee",
                 "support"
               ]
      end
    end

    describe "transactions" do
      test "a hybrid transaction's form and scheme", %{conn: conn} do
        transaction =
          :transaction
          |> insert(
            shn_version: 1,
            shn_form: "hybrid",
            shn_pq_scheme: 0x20,
            shn_metadata_hash: full_hash(@metadata_hash)
          )
          |> with_block()

        expected = %{
          "version" => 1,
          "form" => "hybrid",
          "pq_scheme" => %{"id" => 32, "name" => "FN-DSA-512 (pre-standard)"},
          "pq_sender_hash" => nil,
          "metadata_hash" => @metadata_hash,
          "operation" => nil
        }

        response = conn |> get("/api/v2/transactions/#{transaction.hash}") |> json_response(200)
        assert response["shinerium"] == expected

        response = conn |> get("/api/v2/transactions") |> json_response(200)
        assert [%{"shinerium" => ^expected}] = response["items"]
      end

      test "an Ethereum form and an unknown scheme", %{conn: conn} do
        ethereum = :transaction |> insert(shn_version: 0) |> with_block()

        response = conn |> get("/api/v2/transactions/#{ethereum.hash}") |> json_response(200)

        assert response["shinerium"] == %{
                 "version" => 0,
                 "form" => nil,
                 "pq_scheme" => nil,
                 "pq_sender_hash" => nil,
                 "metadata_hash" => nil,
                 "operation" => nil
               }

        unknown = :transaction |> insert(shn_version: 1, shn_form: "hybrid", shn_pq_scheme: 0x7E) |> with_block()
        response = conn |> get("/api/v2/transactions/#{unknown.hash}") |> json_response(200)
        assert response["shinerium"]["pq_scheme"] == %{"id" => 126, "name" => "unknown (0x7E)"}

        retired = :transaction |> insert(shn_version: 1, shn_form: "hybrid", shn_pq_scheme: 0x05) |> with_block()
        response = conn |> get("/api/v2/transactions/#{retired.hash}") |> json_response(200)
        assert response["shinerium"]["pq_scheme"] == %{"id" => 5, "name" => "retired (0x05)"}
      end
    end

    describe "system contract operations" do
      # From the explorer's fixture of the node's encodings
      # (apps/explorer/test/support/fixture/shinerium/system_calls.json).
      @vote_yes "0xf86d02a0111111111111111111111111111111111111111111111111111111111111111180010780808080a0" <>
                  String.duplicate("00", 32) <> "01a0" <> String.duplicate("66", 32) <> "80"
      @register "0xd5012088565656565656565602883333333333333333"

      # A system contract's code is empty, as the node's eth_getCode answers.
      defp system_call(address, input) do
        {:ok, no_code} = Data.cast("0x")
        to_address = insert(:address, hash: address, contract_code: no_code)
        {:ok, input} = Data.cast(input)

        :transaction
        |> insert(to_address: to_address, to_address_hash: to_address.hash, input: input)
        |> with_block()
      end

      @no_fields %{
        "identity" => nil,
        "proposal" => nil,
        "kind" => nil,
        "choice" => nil,
        "scheme" => nil,
        "policy" => nil,
        "binary" => nil,
        "version" => nil
      }

      test "a council vote is the method `vote`, with its proposal and choice", %{conn: conn} do
        transaction = system_call("0x0000000000000000000000000000000000000107", @vote_yes)

        expected =
          Map.merge(@no_fields, %{
            "contract" => "Council",
            "code" => 2,
            "name" => "vote",
            "identity" => "0x" <> String.duplicate("11", 32),
            "proposal" => 7,
            "choice" => "yes"
          })

        response = conn |> get("/api/v2/transactions/#{transaction.hash}") |> json_response(200)
        assert response["method"] == "vote"
        assert response["shinerium"]["operation"] == expected

        response = conn |> get("/api/v2/transactions") |> json_response(200)
        assert [%{"method" => "vote", "shinerium" => %{"operation" => ^expected}}] = response["items"]
      end

      test "a key's registration names its scheme and policy", %{conn: conn} do
        transaction = system_call("0x0000000000000000000000000000000000000106", @register)

        response = conn |> get("/api/v2/transactions/#{transaction.hash}") |> json_response(200)
        assert response["method"] == "register"

        assert response["shinerium"]["operation"] ==
                 Map.merge(@no_fields, %{
                   "contract" => "AccountKeys",
                   "code" => 1,
                   "name" => "register",
                   "scheme" => %{"id" => 32, "name" => "FN-DSA-512 (pre-standard)"},
                   "policy" => "required"
                 })
      end

      test "an unknown operation keeps the method the input gives", %{conn: conn} do
        # operation 12 of the bond, unknown to the explorer: the first four bytes stay the method
        transaction = system_call("0x0000000000000000000000000000000000000102", "0xc50c80808080")

        response = conn |> get("/api/v2/transactions/#{transaction.hash}") |> json_response(200)
        assert response["method"] == "0xc50c8080"

        assert response["shinerium"]["operation"] ==
                 Map.merge(@no_fields, %{"contract" => "ValidatorBond", "code" => 12, "name" => nil})
      end
    end

    describe "an account's key and vesting" do
      setup :verify_on_exit!

      @pool "0xa57a71d381a20000000000000000000000000002"
      @key_hash "0x" <> String.duplicate("ab", 32)

      defp node_answers(address, account_key, vesting) do
        EthereumJSONRPC.Mox
        |> expect(:json_rpc, fn %{method: "shn_getAccountKey", params: [^address, "latest"]}, _ -> account_key end)
        |> expect(:json_rpc, fn %{method: "shn_getVesting", params: [^address, "latest"]}, _ -> vesting end)
      end

      test "a grant pool with a required key, as the node gives it", %{conn: conn} do
        node_answers(
          @pool,
          {:ok,
           %{
             "address" => @pool,
             "policy" => "required",
             "scheme" => "0x20",
             "schemeName" => "FN-DSA-512 (pre-standard, falcon-go CT)",
             "version" => "0x1",
             "changedAt" => "0x0",
             "keyHash" => @key_hash,
             "verifiable" => true
           }},
          {:ok,
           %{
             "address" => @pool,
             "blockNumber" => "0x24d",
             "time" => "0x6a0a8a40",
             "balance" => "0x6bdd0e563bd56a8000000",
             "lockedUntil" => "0x761977f8",
             "whollyLocked" => false,
             "record" => %{
               "amount" => "0x69bf2c4959db255c00000",
               "start" => "0x6eaf07f8",
               "cliff" => "0x6eaf07f8",
               "end" => "0x761977f8",
               "step" => "0x278d00",
               "pool" => true
             },
             "vested" => "0x0",
             "nextVest" => "0x6ed694f8",
             "locked" => "0x69bf2c4959db255c00000",
             "spendable" => "0x21e19e0c9bab2400000"
           }}
        )

        response = conn |> get("/api/v2/shinerium/addresses/#{@pool}") |> json_response(200)

        assert response == %{
                 "account_key" => %{
                   "policy" => "required",
                   "scheme" => %{"id" => 32, "name" => "FN-DSA-512 (pre-standard)"},
                   "version" => 1,
                   "changed_at_block" => 0,
                   "key_hash" => @key_hash,
                   "verifiable" => true
                 },
                 "vesting" => %{
                   "locked_until" => "2032-10-14T15:30:00Z",
                   "wholly_locked" => false,
                   "locked" => "7990000000000000000000000",
                   "spendable" => "10000000000000000000000",
                   "vested" => "0",
                   "next_vest" => "2028-12-04T15:30:00Z",
                   "record" => %{
                     "amount" => "7990000000000000000000000",
                     "start" => "2028-11-04T15:30:00Z",
                     "cliff" => "2028-11-04T15:30:00Z",
                     "end" => "2032-10-14T15:30:00Z",
                     "step" => 2_592_000,
                     "pool" => true
                   }
                 }
               }
      end

      test "an account with neither key nor vesting", %{conn: conn} do
        address = "0x2b2a63c920f8b7a3f1c1b2e5d6a0e8c3f4a5b6c7"

        node_answers(
          address,
          {:ok,
           %{
             "address" => address,
             "policy" => "none",
             "scheme" => "0x0",
             "version" => "0x0",
             "changedAt" => "0x0",
             "keyHash" => "0x" <> String.duplicate("0", 64),
             "verifiable" => false
           }},
          {:ok,
           %{
             "address" => address,
             "lockedUntil" => "0x0",
             "whollyLocked" => false,
             "record" => nil,
             "locked" => "0x0",
             "spendable" => "0x0"
           }}
        )

        response = conn |> get("/api/v2/shinerium/addresses/#{address}") |> json_response(200)

        assert response == %{
                 "account_key" => %{
                   "policy" => "none",
                   "scheme" => nil,
                   "version" => 0,
                   "changed_at_block" => 0,
                   "key_hash" => nil,
                   "verifiable" => false
                 },
                 "vesting" => %{
                   "locked_until" => nil,
                   "wholly_locked" => false,
                   "locked" => "0",
                   "spendable" => "0",
                   "vested" => nil,
                   "next_vest" => nil,
                   "record" => nil
                 }
               }
      end

      test "what the node does not give is null", %{conn: conn} do
        unknown_method = {:error, %{code: -32_601, message: "the method shn_getVesting does not exist"}}
        node_answers(@pool, {:error, :timeout}, unknown_method)

        response = conn |> get("/api/v2/shinerium/addresses/#{@pool}") |> json_response(200)
        assert response == %{"account_key" => nil, "vesting" => nil}
      end

      test "an address that is no address", %{conn: conn} do
        conn |> get("/api/v2/shinerium/addresses/0x123") |> json_response(422)
      end
    end

    describe "addresses" do
      test "the total supply is the latest header's", %{conn: conn} do
        carrier()

        response = conn |> get("/api/v2/addresses") |> json_response(200)
        assert response["total_supply"] == "200000986.577454855327738357"
      end
    end

    describe "epochs, committees and validators (P4)" do
      alias Explorer.Chain.Shinerium.Consensus

      @members [
        {"0x7a8c7e56b6d2741a685511134b3e7e44c7a044784566e2c84e91816a730ea791",
         "0x62adbfea805c0baf48b88a9e8c011dae7e450765", "SCM01"},
        {"0xccc31774059cb9bb8b667e3693d31052f555e6328b18f73c79ac862b78530a18",
         "0x9434c7b49e217ba9a65c427b8de9cff2c77fde80", nil},
        {"0x9b4aaa715ee4937d00c421147e3d88b5689729af989282d2dce8716789315e5a",
         "0xfc74dc5766df64f5a9ab70cb8fd6bfc51baf9368", "SCM03"}
      ]

      @location %{"country" => "CA", "region" => "Quebec", "asn" => 16_276, "source" => "declared"}
      @measured %{"country" => "DE", "region" => "Hesse", "asn" => 24_940, "source" => "measured"}

      defp member_rows(epoch, signed, removed, record \\ %{}) do
        @members
        |> Enum.with_index()
        |> Enum.map(fn {{identity, address, _name}, index} ->
          %{
            epoch_number: epoch,
            index: index,
            identity: full_hash(identity),
            ed_address_hash: address_hash(address),
            coinbase_hash: address_hash("0x0b5f7268a8081e9b871c902b3bd968443b3fa173"),
            pq_key_hash: full_hash("0x" <> String.duplicate("f9", 32)),
            location: (record[:locations] && Enum.at(record[:locations], index)) || @location,
            signed: signed && Enum.at(signed, index),
            correlated: record[:correlated] && Enum.at(record[:correlated], index),
            slow: record[:slow] && Enum.at(record[:slow], index),
            removal_reason: Map.get(removed, index)
          }
        end)
      end

      defp epoch_row(number, ended?) do
        %{
          number: number,
          control_block_hash: full_hash("0x" <> String.duplicate("0#{number}", 32)),
          committee_hash: full_hash("0x" <> String.duplicate("c#{number}", 32)),
          started_at: ~U[2026-11-06 10:00:00.000000Z] |> DateTime.add(number * 600),
          carrier_block_number: number * 10,
          members_count: 3,
          ended_at: if(ended?, do: ~U[2026-11-06 10:00:00.000000Z] |> DateTime.add(number * 600 + 600)),
          end_block_number: if(ended?, do: number * 10 + 10),
          qcs: if(ended?, do: 4),
          absent_kept: if(ended?, do: 0),
          next_first: if(ended?, do: 1),
          record_complete: ended?,
          joined:
            if(ended?,
              do: [
                %{
                  "edPublic" => "AB" <> String.duplicate("cd", 31),
                  "edAddress" => "0x936B096aeDa0DB3195Df7d3c4D6585098E5643E1",
                  "coinbase" => "0x936B096aeDa0DB3195Df7d3c4D6585098E5643E1",
                  "location" => %{"country" => "GB"}
                }
              ]
            )
        }
      end

      # Epoch 6 ended: member 1 signed 2 of 4 and left as offline. Members 1 and 2,
      # of one autonomous system, both missed one certificate, which counts twice
      # for each, so they are credited with 1 and 2. Member 2 had been found slow
      # in the two epochs before, member 1 in one. Epoch 7 runs; the beacons placed
      # member 2 again when it joined.
      defp epochs do
        {:ok, _} =
          Consensus.import_epochs(
            [epoch_row(6, true), epoch_row(7, false)],
            member_rows(6, [4, 2, 3], %{1 => 2}, %{correlated: [0, 3, 2], slow: [0, 1, 2]}) ++
              member_rows(7, nil, %{}, %{slow: [0, 0, 1], locations: [nil, nil, @measured]})
          )

        Consensus.upsert_validators(
          Enum.map(@members, fn {identity, address, _} ->
            %{identity: full_hash(identity), ed_address_hash: address_hash(address)}
          end)
        )

        Consensus.upsert_validators(
          for {identity, address, name} <- @members, name do
            %{
              identity: full_hash(identity),
              ed_address_hash: address_hash(address),
              name: name,
              status: "active",
              genesis: true,
              amount: %Wei{value: Decimal.new(100_000_000_000_000_000_000_000)},
              bond_owner_hash: address_hash("0xb67a9585b0d8b6d3b1b8e7e5a2a9d6f1c3e4b5a6"),
              refund_address_hash: address_hash("0xb67a9585b0d8b6d3b1b8e7e5a2a9d6f1c3e4b5a6"),
              bls_hash: full_hash("0x" <> String.duplicate("b1", 32)),
              pq_hash: full_hash("0x" <> String.duplicate("e5", 32)),
              active_at: 0,
              exiting: false,
              release_at: nil,
              forced_exit: false,
              required: %Wei{value: Decimal.new(100_000_000_000_000_000_000_000)},
              shortfall: %Wei{value: Decimal.new(0)},
              penalty: nil,
              penalty_box: %{
                "seat_from" => 0,
                "since" => 0,
                "strikes" => 0,
                "reason" => 0,
                "reason_name" => nil,
                "active" => false,
                "epochs_left" => 0
              },
              bond_block_number: 70
            }
          end
        )

        block = insert(:block, number: 70)

        for {{_, address, _}, amount} <- Enum.zip(@members, [40, 20, 30]) do
          insert(:withdrawal,
            block: block,
            block_hash: block.hash,
            validator_index: 6,
            amount: %Wei{value: Decimal.new(amount * 1_000_000_000_000_000_000)},
            shn_reward_type: "committee",
            shn_validator_hash: address_hash(address)
          )
        end

        insert(:withdrawal, block: block, block_hash: block.hash, validator_index: 6, shn_reward_type: "support")
        :ok
      end

      test "the epochs, the newest first, the running one current", %{conn: conn} do
        epochs()
        response = conn |> get("/api/v2/shinerium/epochs") |> json_response(200)

        assert [running, ended] = response["items"]
        assert response["next_page_params"] == nil

        assert %{"number" => 7, "is_current" => true, "ended_at" => nil, "qcs" => nil, "signed" => nil} = running
        assert %{"first_block_number" => 71, "end_block_number" => nil, "members_count" => 3} = running

        assert %{"number" => 6, "is_current" => false, "qcs" => 4, "signed" => 9, "removed_count" => 1} = ended
        assert %{"first_block_number" => 61, "end_block_number" => 70, "joined_count" => 1} = ended
        assert ended["started_at"] == "2026-11-06T11:00:00.000000Z"

        response = conn |> get("/api/v2/shinerium/epochs", %{"number" => "7"}) |> json_response(200)
        assert Enum.map(response["items"], & &1["number"]) == [6]
      end

      test "an epoch's committee: names, signatures, removals, rewards and the nodes that join", %{conn: conn} do
        epochs()
        response = conn |> get("/api/v2/shinerium/epochs/6") |> json_response(200)

        assert %{"number" => 6, "next_first" => 1, "signed" => 9, "removed_count" => 1} = response
        assert [first, second, third] = response["members"]

        assert first["name"] == "SCM01"
        assert first["identity"] == "0x7a8c7e56b6d2741a685511134b3e7e44c7a044784566e2c84e91816a730ea791"
        assert first["ed_address_hash"] == "0x62adbfea805c0baf48b88a9e8c011dae7e450765"
        assert {first["signed"], first["removal"], first["reward"]} == {4, nil, "40000000000000000000"}
        assert first["location"]["country"] == "CA"

        assert {second["name"], second["signed"]} == {nil, 2}
        assert second["removal"] == %{"code" => 2, "name" => "offline"}
        assert {third["index"], third["reward"]} == {2, "30000000000000000000"}

        assert Enum.map(response["members"], &{&1["signed"], &1["correlated"], &1["credited"], &1["slow"]}) ==
                 [{4, 0, 4, 0}, {2, 3, 1, 1}, {3, 2, 2, 2}]

        assert [joined] = response["joined"]
        assert joined["identity"] == "0xab" <> String.duplicate("cd", 31)
        assert joined["ed_address_hash"] == "0x936b096aeda0db3195df7d3c4d6585098e5643e1"

        running = conn |> get("/api/v2/shinerium/epochs/7") |> json_response(200)
        assert running["members"] |> Enum.map(&{&1["signed"], &1["reward"]}) |> Enum.uniq() == [{nil, nil}]
        assert Enum.map(running["members"], &{&1["credited"], &1["slow"]}) == [{nil, 0}, {nil, 0}, {nil, 1}]
        assert {running["joined"], running["signed"], running["removed_count"]} == {nil, nil, nil}

        assert conn |> get("/api/v2/shinerium/epochs/8") |> json_response(404)
      end

      test "the validators, the committee's first, with their epochs, signatures and rewards", %{conn: conn} do
        epochs()

        # an identity seen only among the nodes joining a committee
        Consensus.upsert_validators([
          %{
            identity: full_hash("0x" <> String.duplicate("ee", 32)),
            ed_address_hash: address_hash("0x00000000000000000000000000000000000000ee")
          }
        ])

        response = conn |> get("/api/v2/shinerium/validators") |> json_response(200)
        assert length(response["items"]) == 4

        [scm01 | _] = response["items"]
        assert %{"name" => "SCM01", "is_member" => true, "epochs" => 2, "first_epoch" => 6, "last_epoch" => 7} = scm01
        assert %{"signed" => 4, "qcs" => 4, "status" => "active", "genesis" => true} = scm01
        assert %{"rewards_total" => "40000000000000000000", "rewards_count" => 1} = scm01
        assert {scm01["location"], scm01["location_epoch"]} == {@location, 7}

        # its latest epoch's location, where the beacons placed it when it joined
        scm03 = Enum.find(response["items"], &(&1["name"] == "SCM03"))
        assert %{"location" => %{"country" => "DE", "source" => "measured"}, "location_epoch" => 7} = scm03

        outsider = List.last(response["items"])

        assert %{"is_member" => false, "epochs" => 0, "signed" => nil, "rewards_total" => nil, "status" => nil} =
                 outsider

        assert {outsider["location"], outsider["location_epoch"]} == {nil, nil}
      end

      test "a validator by its identity or its address, its bond and its epochs", %{conn: conn} do
        epochs()
        {identity, address, _} = hd(@members)

        response = conn |> get("/api/v2/shinerium/validators/#{identity}") |> json_response(200)
        assert response == conn |> get("/api/v2/shinerium/validators/#{address}") |> json_response(200)

        assert %{"name" => "SCM01", "amount" => "100000000000000000000000", "shortfall" => "0"} = response
        assert %{"bond_block_number" => 70, "release_at" => nil, "penalty" => nil} = response
        assert response["penalty_box"]["active"] == false
        assert {response["location"], response["location_epoch"]} == {@location, 7}

        response = conn |> get("/api/v2/shinerium/validators/#{identity}/epochs") |> json_response(200)
        assert [running, ended] = response["items"]
        assert {running["epoch_number"], running["signed"], running["qcs"]} == {7, nil, nil}

        assert %{"epoch_number" => 6, "index" => 0, "signed" => 4, "qcs" => 4, "reward" => "40000000000000000000"} =
                 ended

        assert {running["credited"], running["slow"]} == {nil, 0}
        assert %{"correlated" => 0, "credited" => 4, "slow" => 0} = ended

        {other, _, _} = Enum.at(@members, 1)
        response = conn |> get("/api/v2/shinerium/validators/#{other}/epochs") |> json_response(200)
        assert List.last(response["items"])["removal"] == %{"code" => 2, "name" => "offline"}
        assert %{"signed" => 2, "correlated" => 3, "credited" => 1, "slow" => 1} = List.last(response["items"])

        assert conn |> get("/api/v2/shinerium/validators/0x#{String.duplicate("11", 32)}") |> json_response(404)
        assert conn |> get("/api/v2/shinerium/validators/0x1234") |> json_response(422)
      end

      test "a block's epoch, view and certificates, their signers named", %{conn: conn} do
        epochs()

        parent = insert(:block, number: 72, shn_epoch: 7, shn_view: 3)

        block =
          insert(:block,
            number: 73,
            parent_hash: parent.hash,
            shn_epoch: 7,
            shn_view: 4,
            shn_justify_epoch: 7,
            shn_justify_view: 3,
            shn_justify_scheme: 1,
            shn_justify_signers: [0, 2]
          )

        insert(:block,
          number: 74,
          parent_hash: block.hash,
          shn_epoch: 7,
          shn_view: 5,
          shn_justify_epoch: 7,
          shn_justify_view: 4,
          shn_justify_scheme: 3,
          shn_justify_signers: [0, 1, 2]
        )

        response = conn |> get("/api/v2/blocks/#{block.number}") |> json_response(200)
        assert %{"epoch" => 7, "view" => 4} = response["shinerium"]
        assert response["shinerium"]["justify"] == %{"epoch" => 7, "view" => 3, "scheme" => 1, "signers_count" => 2}

        response = conn |> get("/api/v2/shinerium/blocks/#{block.number}/consensus") |> json_response(200)
        assert %{"epoch" => 7, "view" => 4} = response

        justify = response["justify"]
        assert {justify["certified_block_number"], justify["carried_by_block_number"]} == {72, 73}
        assert justify["certified_block_hash"] == to_string(parent.hash)
        assert {justify["scheme"], justify["committee_size"]} == {%{"id" => 1, "name" => "BLS"}, 3}
        assert Enum.map(justify["signers"], &{&1["index"], &1["name"]}) == [{0, "SCM01"}, {2, "SCM03"}]

        certificate = response["certificate"]
        assert {certificate["certified_block_number"], certificate["carried_by_block_number"]} == {73, 74}
        assert certificate["scheme"]["id"] == 3
        assert Enum.map(certificate["signers"], & &1["index"]) == [0, 1, 2]

        assert Enum.at(certificate["signers"], 1)["ed_address_hash"] ==
                 "0x9434c7b49e217ba9a65c427b8de9cff2c77fde80"

        response = conn |> get("/api/v2/shinerium/blocks/#{parent.hash}/consensus") |> json_response(200)
        assert response["justify"] == nil
        assert response["certificate"]["carried_by_block_number"] == 73
      end
    end
  end
end
