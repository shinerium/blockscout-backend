# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Explorer.Chain.Shinerium.EpochTest do
  use ExUnit.Case, async: true

  alias Explorer.Chain.Shinerium.Epoch

  # The seal nonces of the node's blockseal/beaconhash/porc: generation << 16 |
  # version << 8 | tier, the base generation writing no generation byte
  # (docs/design/porc/porc-generations.md, section 3; block-explorer-plan 11.30).
  describe "joined_seal/1" do
    test "the rehearsal's generation 3, version 2, the basic tier" do
      assert Epoch.joined_seal(%Epoch{joined_seal_nonce: 0x030203}) ==
               %{nonce: 0x030203, porc_generation: 3, porc_version: 2, tier: "basic"}
    end

    test "a seal of the base generation names none, and is generation 2" do
      assert %{porc_generation: 2, porc_version: 2, tier: "validator"} =
               Epoch.joined_seal(%Epoch{joined_seal_nonce: 0x0201})
    end

    test "a tier the node does not have is nil" do
      assert %{porc_generation: 4, tier: nil} = Epoch.joined_seal(%Epoch{joined_seal_nonce: 0x040209})
    end

    test "no candidate seated: nil" do
      assert Epoch.joined_seal(%Epoch{joined_seal_nonce: nil}) == nil
      assert Epoch.joined_seal(%Epoch{joined_seal_nonce: 0}) == nil
    end
  end
end
