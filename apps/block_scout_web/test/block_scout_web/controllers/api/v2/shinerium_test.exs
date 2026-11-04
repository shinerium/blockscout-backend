# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule BlockScoutWeb.API.V2.ShineriumTest do
  # The responses are checked against the OpenAPI schema by `json_response/2`.
  use BlockScoutWeb.ConnCase
  use Utils.CompileTimeEnvHelper, chain_type: [:explorer, :chain_type]

  if @chain_type == :shinerium do
    alias Explorer.Chain.{Hash, Wei}

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
          "pq_scheme" => %{"id" => 32, "name" => "FN-DSA-512"},
          "pq_sender_hash" => nil,
          "metadata_hash" => @metadata_hash
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
                 "metadata_hash" => nil
               }

        unknown = :transaction |> insert(shn_version: 1, shn_form: "hybrid", shn_pq_scheme: 0x7E) |> with_block()
        response = conn |> get("/api/v2/transactions/#{unknown.hash}") |> json_response(200)
        assert response["shinerium"]["pq_scheme"] == %{"id" => 126, "name" => "unknown (0x7E)"}
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
