# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule EthereumJSONRPC.Shinerium.QuorumCertificate do
  @moduledoc """
  The quorum certificate a Shinerium block carries in its `justify`: the
  certificate of its parent, as the node's `smartfhs.QC` encodes it, the RLP
  list `[epoch, view, block, signers, scheme, signature]` (the node's
  docs/reference/eth-rpc.md, "Consensus in the block JSON").

  `signers` is a bitmap over the committee's indices, bit i in byte i/8, the
  lowest bit first; it is read into the list of indices. The signature itself
  is not kept, only its size: a scheme 1 certificate has one BLS aggregate of
  96 bytes, and a scheme 3 (hybrid) certificate that aggregate followed by one
  ML-DSA-44 signature of 2 420 bytes for each signer.
  """

  alias EthereumJSONRPC.Shinerium.RLP

  @type t :: %{
          epoch: non_neg_integer(),
          view: non_neg_integer(),
          block_hash: String.t(),
          signers: [non_neg_integer()],
          scheme: non_neg_integer(),
          signature_size: non_neg_integer()
        }

  @doc """
  Decodes a `justify` as the node serves it, hex data, or its bytes.

      iex> EthereumJSONRPC.Shinerium.QuorumCertificate.decode(
      ...>   "0xe68080a00000000000000000000000000000000000000000000000000000000000000000808080"
      ...> )
      {:ok,
       %{
         epoch: 0,
         view: 0,
         block_hash: "0x0000000000000000000000000000000000000000000000000000000000000000",
         signers: [],
         scheme: 0,
         signature_size: 0
       }}

      iex> EthereumJSONRPC.Shinerium.QuorumCertificate.decode("0xc0")
      :error
  """
  @spec decode(String.t() | binary() | nil) :: {:ok, t()} | :error
  def decode("0x" <> hex) do
    case Base.decode16(hex, case: :mixed) do
      {:ok, bytes} -> decode(bytes)
      :error -> :error
    end
  end

  def decode(bytes) when is_binary(bytes) do
    with {:ok, [epoch, view, {:string, <<_::binary-size(32)>> = hash}, {:string, signers}, scheme, {:string, sig}]} <-
           RLP.list(bytes),
         {:ok, epoch} <- RLP.uint(epoch),
         {:ok, view} <- RLP.uint(view),
         {:ok, scheme} when scheme <= 255 <- RLP.uint(scheme) do
      {:ok,
       %{
         epoch: epoch,
         view: view,
         block_hash: "0x" <> Base.encode16(hash, case: :lower),
         signers: bitmap_indices(signers),
         scheme: scheme,
         signature_size: byte_size(sig)
       }}
    else
      _ -> :error
    end
  end

  def decode(_), do: :error

  @doc """
  The committee indices a signer bitmap holds, in ascending order.

      iex> EthereumJSONRPC.Shinerium.QuorumCertificate.bitmap_indices(<<0x09, 0x09>>)
      [0, 3, 8, 11]
  """
  @spec bitmap_indices(binary()) :: [non_neg_integer()]
  def bitmap_indices(bitmap) when is_binary(bitmap) do
    for {byte, i} <- Enum.with_index(:binary.bin_to_list(bitmap)),
        bit <- 0..7,
        Bitwise.band(byte, Bitwise.bsl(1, bit)) != 0,
        do: i * 8 + bit
  end
end
