# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Explorer.Chain.Shinerium.EpochMemberTest do
  use ExUnit.Case, async: true

  alias Explorer.Chain.Shinerium.{Epoch, EpochMember}

  # Epoch 217 of the 0.2.0 network (blocks 2953–2984): its record's signatures
  # and correlated misses, and what the carrier paid each member for, as FHS's
  # line of 7 November gives them (block-explorer-plan 11.18).
  @qcs 31
  @signed [29, 27, 26, 30, 30, 24, 31]
  @correlated [4, 8, 10, 2, 2, 14, 0]
  @paid_for [27, 23, 21, 29, 29, 17, 31]

  defp ended(record_complete), do: %Epoch{number: 217, qcs: @qcs, record_complete: record_complete}

  describe "credited/2" do
    test "under the correlation penalty, the certificates less the correlated misses" do
      credited =
        Enum.zip_with(@signed, @correlated, fn signed, correlated ->
          EpochMember.credited(%EpochMember{signed: signed, correlated: correlated}, ended(true))
        end)

      assert credited == @paid_for
    end

    test "never below zero" do
      assert EpochMember.credited(%EpochMember{signed: 0, correlated: 40}, ended(true)) == 0
    end

    test "on a network without the penalty, the certificates signed" do
      assert EpochMember.credited(%EpochMember{signed: 24, correlated: nil}, ended(true)) == 24
    end

    test "nothing from a record read without correlated, nor while the epoch runs" do
      assert EpochMember.credited(%EpochMember{signed: 24, correlated: nil}, ended(false)) == nil
      assert EpochMember.credited(%EpochMember{signed: nil, correlated: nil}, %Epoch{number: 218}) == nil
    end
  end
end
