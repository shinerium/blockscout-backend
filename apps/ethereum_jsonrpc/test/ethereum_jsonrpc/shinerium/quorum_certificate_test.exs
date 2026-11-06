# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule EthereumJSONRPC.Shinerium.QuorumCertificateTest do
  use ExUnit.Case, async: true

  alias EthereumJSONRPC.Shinerium.{QuorumCertificate, RLP}

  doctest RLP
  doctest QuorumCertificate

  # Encoded by the node's smartfhs.QC.Encode() (0.2.0-39ebea86).
  @bls "0xf88b82011f82100aa03d0514715ed027b78d0cb6cb4a56a3e20bc34950130b2be93b36310f3a13f38a6f01b860" <>
         String.duplicate("ab", 96)

  # A hybrid certificate of a committee of twelve, members 0, 3, 8 and 11
  # signing: the BLS aggregate and four ML-DSA-44 signatures, 9 776 bytes.
  @hybrid "0xf9265a0501a0" <>
            String.duplicate("00", 31) <> "01" <> "820909" <> "03" <> "b92630" <> String.duplicate("cd", 9_776)

  test "reads a BLS certificate" do
    assert {:ok, qc} = QuorumCertificate.decode(@bls)

    assert qc == %{
             epoch: 287,
             view: 4106,
             block_hash: "0x3d0514715ed027b78d0cb6cb4a56a3e20bc34950130b2be93b36310f3a13f38a",
             signers: [0, 1, 2, 3, 5, 6],
             scheme: 1,
             signature_size: 96
           }
  end

  test "reads a hybrid certificate, its signers in a bitmap of two bytes" do
    assert {:ok, qc} = QuorumCertificate.decode(@hybrid)
    assert {qc.epoch, qc.view, qc.scheme, qc.signers, qc.signature_size} == {5, 1, 3, [0, 3, 8, 11], 9_776}
    assert qc.block_hash == "0x" <> String.duplicate("00", 31) <> "01"
  end

  test "reads the bytes as the hex" do
    "0x" <> hex = @bls
    assert QuorumCertificate.decode(Base.decode16!(hex, case: :lower)) == QuorumCertificate.decode(@bls)
  end

  test "refuses what is not a certificate" do
    "0xf88b" <> body = @bls

    for input <- [
          nil,
          "0x",
          "0xzz",
          # one byte short
          String.slice(@bls, 0..-3//1),
          # a byte too many after the list
          @bls <> "00",
          # a block hash of 31 bytes
          "0xf88a82011f82100a9f" <> String.duplicate("11", 31) <> "6f01b860" <> String.duplicate("ab", 96),
          # an epoch with a leading zero
          "0xf88c8300011f" <> String.slice(body, 6..-1//1),
          # five items
          "0xc50102030405"
        ] do
      assert QuorumCertificate.decode(input) == :error, inspect(input)
    end
  end

  test "an RLP uint holds at most eight bytes" do
    assert RLP.uint(<<1, 2, 3, 4, 5, 6, 7, 8>>) == {:ok, 0x0102030405060708}
    assert RLP.uint(<<1, 2, 3, 4, 5, 6, 7, 8, 9>>) == :error
    assert RLP.uint(<<>>) == {:ok, 0}
  end
end
