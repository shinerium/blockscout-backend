# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Explorer.Chain.Shinerium.EpochMember do
  @moduledoc """
  A member of an epoch's committee, at its committee index, as the node's
  `shn_committeeMembers` gives it, with what the record at the epoch's end
  says of it: the certificates it signed, and why it left, if it did.
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
    field(:removal_reason, :integer)

    timestamps()
  end
end
