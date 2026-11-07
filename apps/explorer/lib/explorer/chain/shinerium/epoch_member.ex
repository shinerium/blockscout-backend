# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Explorer.Chain.Shinerium.EpochMember do
  @moduledoc """
  A member of an epoch's committee, at its committee index, as the node's
  `shn_committeeMembers` gives it, with what the records say of it: the one at
  the epoch's end, the certificates it signed, its correlated misses and why it
  left, if it did; the one that seats the committee, how many epochs before
  had found it slow.
  """

  use Explorer.Schema

  alias Explorer.Chain.Hash
  alias Explorer.Chain.Shinerium.Epoch

  @typedoc """
  * `epoch_number` - the epoch.
  * `index` - the member's index in the epoch's committee.
  * `identity` - its Ed25519 identity key.
  * `ed_address_hash` - the identity's address.
  * `coinbase_hash` - the address its rewards go to.
  * `pq_key_hash` - the Keccak-256 hash of its ML-DSA-44 key.
  * `location` - where the beacons placed it, or what the genesis declares.
  * `signed` - the epoch's certificates it signed; nil while the epoch runs.
  * `correlated` - its correlated misses: each certificate it did not sign
    counts as many times as members of its autonomous system did not sign it,
    itself included, at most f + 1. Nil while the epoch runs, on a network
    without the correlation penalty, or from a record read without them.
  * `slow` - the consecutive epochs before this one that found it slow, from
    the record of the control block that seats the committee; at two it leads
    no views. Nil for the genesis's committee or from a record read without it.
  * `removal_reason` - why it left at the epoch's end; nil if it stays.
  """
  @primary_key false
  typed_schema "shinerium_epoch_members" do
    belongs_to(:epoch, Epoch,
      foreign_key: :epoch_number,
      references: :number,
      type: :integer,
      primary_key: true
    )

    field(:index, :integer, primary_key: true)
    field(:identity, Hash.Full, null: false)
    field(:ed_address_hash, Hash.Address, null: false)
    field(:coinbase_hash, Hash.Address)
    field(:pq_key_hash, Hash.Full)
    field(:location, :map)
    field(:signed, :integer)
    field(:correlated, :integer)
    field(:slow, :integer)
    field(:removal_reason, :integer)

    timestamps()
  end

  @doc """
  What the carrier that ends the epoch credits the member with, the count its
  share of the reward is scaled by (the node's `Committee.rewardEpoch`):
  under the correlation penalty the epoch's certificates less the member's
  correlated misses, on a network without it the certificates it signed. Nil
  while the epoch runs, or when its record was read from a node that did not
  serve `correlated` (block-explorer-plan 11.18).
  """
  @spec credited(t(), Epoch.t()) :: non_neg_integer() | nil
  def credited(%__MODULE__{correlated: correlated}, %Epoch{qcs: qcs})
      when is_integer(correlated) and is_integer(qcs),
      do: qcs - min(qcs, correlated)

  def credited(%__MODULE__{signed: signed}, %Epoch{record_complete: true}) when is_integer(signed), do: signed
  def credited(_member, _epoch), do: nil
end
