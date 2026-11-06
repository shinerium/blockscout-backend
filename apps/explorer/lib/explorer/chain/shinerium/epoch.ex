# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Explorer.Chain.Shinerium.Epoch do
  @moduledoc """
  An epoch of the Shinerium chain: the one control block `number` starts.

  Its blocks follow the carrier of that control block, up to the carrier of
  control block `number + 1`, which ends the epoch and carries the record of
  how it went (the node's `EpochChange`): how many quorum certificates its
  blocks carried, how many each member signed, who left and why, who joined.
  Until then the fields from that record are nil.
  """

  use Explorer.Schema

  alias Explorer.Chain.Hash
  alias Explorer.Chain.Shinerium.EpochMember

  # The node's Eviction constants (core/protocol/controlblock.go and
  # controlblock_epoch.go): why a member leaves the committee.
  @removal_reasons %{
    1 => "banned",
    2 => "offline",
    3 => "outranked",
    4 => "rotated",
    5 => "exited",
    6 => "shrunk",
    7 => "outdated",
    8 => "slow",
    9 => "crowded",
    10 => "unevaluated",
    11 => "underbonded",
    12 => "foundation"
  }

  @typedoc """
  * `number` - the number of the control block that starts the epoch.
  * `control_block_hash` - its hash.
  * `committee_hash` - the hash of the committee it seats.
  * `started_at` - its time.
  * `carrier_block_number` - the block that carries it; nil for the genesis's.
  * `members_count` - the size of the committee.
  * `ended_at` - the time of the control block that ends the epoch.
  * `end_block_number` - the block that carries that one, the epoch's last.
  * `qcs` - the quorum certificates the epoch's blocks carry as justification.
  * `absent_kept` - the members absent at its end that stay in the committee.
  * `next_first` - the committee index of the member the next committee starts with.
  * `joined` - the nodes that join at its end, best first.
  """
  @primary_key {:number, :integer, autogenerate: false}
  typed_schema "shinerium_epochs" do
    field(:control_block_hash, Hash.Full, null: false)
    field(:committee_hash, Hash.Full)
    field(:started_at, :utc_datetime_usec, null: false)
    field(:carrier_block_number, :integer)
    field(:members_count, :integer, null: false)
    field(:ended_at, :utc_datetime_usec)
    field(:end_block_number, :integer)
    field(:qcs, :integer)
    field(:absent_kept, :integer)
    field(:next_first, :integer)
    field(:joined, {:array, :map})

    has_many(:members, EpochMember, foreign_key: :epoch_number, references: :number)

    timestamps()
  end

  @doc """
  The name of a removal reason, nil for none or one the explorer does not know.
  """
  @spec removal_reason_name(non_neg_integer() | nil) :: String.t() | nil
  def removal_reason_name(reason), do: Map.get(@removal_reasons, reason)

  @doc """
  The first block of an epoch: the one after its control block's carrier, or
  block 1 in the genesis's epoch.
  """
  @spec first_block_number(t()) :: non_neg_integer()
  def first_block_number(%__MODULE__{carrier_block_number: nil}), do: 1
  def first_block_number(%__MODULE__{carrier_block_number: carrier}), do: carrier + 1
end
