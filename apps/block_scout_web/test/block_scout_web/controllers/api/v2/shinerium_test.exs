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
      "anchor_chain_hash" => nil
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
  end
end
