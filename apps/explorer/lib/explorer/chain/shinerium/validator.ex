# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Explorer.Chain.Shinerium.Validator do
  @moduledoc """
  A validator identity the explorer has seen in a committee, or among the
  nodes joining one, with its bond as the node's `shn_getValidator` gives it
  (R5 of block-explorer-plan 6.3). The bond's fields are nil until a node that
  serves the method has been asked.
  """

  use Explorer.Schema

  alias Explorer.Chain.{Hash, Wei}

  @typedoc """
  * `identity` - the Ed25519 identity key.
  * `ed_address_hash` - its address.
  * `name` - the name the validator gave itself (the bond's operation 7).
  * `status` - the bond's status: none, pending, active, exiting, releasing,
    releasable or released.
  * `genesis` - whether the genesis made the bond.
  * `amount` - the bond's amount.
  * `bond_owner_hash`, `refund_address_hash` - its owner and refund address.
  * `bls_hash`, `pq_hash` - the hashes of its BLS and post-quantum keys.
  * `active_at` - the block from which the bond is active.
  * `exiting` - whether it asked to exit, or was made to.
  * `release_at` - when its release delay ends.
  * `forced_exit` - whether conflict evidence excluded it.
  * `required`, `shortfall` - the collateral in force and what the bond lacks of it.
  * `penalty` - a forced exit's penalty.
  * `penalty_box` - the penalty box, in the epoch of the block read.
  * `bond_block_number` - the block the bond was read at.
  """
  @primary_key {:identity, Hash.Full, autogenerate: false}
  typed_schema "shinerium_validators" do
    field(:ed_address_hash, Hash.Address, null: false)
    field(:name, :string)
    field(:status, :string)
    field(:genesis, :boolean)
    field(:amount, Wei)
    field(:bond_owner_hash, Hash.Address)
    field(:refund_address_hash, Hash.Address)
    field(:bls_hash, Hash.Full)
    field(:pq_hash, Hash.Full)
    field(:active_at, :integer)
    field(:exiting, :boolean)
    field(:release_at, :utc_datetime_usec)
    field(:forced_exit, :boolean)
    field(:required, Wei)
    field(:shortfall, Wei)
    field(:penalty, :map)
    field(:penalty_box, :map)
    field(:bond_block_number, :integer)

    timestamps()
  end
end
