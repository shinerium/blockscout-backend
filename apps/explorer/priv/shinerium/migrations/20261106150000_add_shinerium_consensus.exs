# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Explorer.Repo.Shinerium.Migrations.AddShineriumConsensus do
  use Ecto.Migration

  # P4 (block-explorer-plan 6.1, stage B): the consensus of each block, as the
  # node's block JSON has it from R4, and the epochs, their committees and the
  # validators, as `Indexer.Fetcher.Shinerium.Epochs` reads them from the node's
  # control blocks (`shn_getControlBlockByNumber`), committees
  # (`shn_committeeMembers`) and bonds (`shn_getValidator`, R5).
  def change do
    alter table(:blocks) do
      # the header's epoch and view; null for a block of no FHS-C view
      add(:shn_epoch, :bigint, null: true)
      add(:shn_view, :bigint, null: true)
      # the parent's quorum certificate, the block's `justify`: its epoch and
      # view, its signature scheme (1 BLS, 3 hybrid) and its signers' indices in
      # that epoch's committee
      add(:shn_justify_epoch, :bigint, null: true)
      add(:shn_justify_view, :bigint, null: true)
      add(:shn_justify_scheme, :smallint, null: true)
      add(:shn_justify_signers, {:array, :smallint}, null: true)
    end

    # Epoch N is the one control block N starts; its blocks are those after the
    # carrier of control block N, up to the carrier of control block N + 1,
    # which ends it and carries the record of how it went.
    create table(:shinerium_epochs, primary_key: false) do
      add(:number, :bigint, null: false, primary_key: true)
      add(:control_block_hash, :bytea, null: false)
      add(:committee_hash, :bytea, null: true)
      add(:started_at, :utc_datetime_usec, null: false)
      # the block that carries control block N, null for the genesis's
      add(:carrier_block_number, :bigint, null: true)
      add(:members_count, :integer, null: false)
      # from control block N + 1, null while the epoch runs
      add(:ended_at, :utc_datetime_usec, null: true)
      add(:end_block_number, :bigint, null: true)
      add(:qcs, :bigint, null: true)
      add(:absent_kept, :integer, null: true)
      # the committee index of the member the next committee starts with
      add(:next_first, :integer, null: true)
      # the nodes that join at its end, best first, without their evidence
      add(:joined, :jsonb, null: true)

      timestamps(null: false, type: :utc_datetime_usec)
    end

    create table(:shinerium_epoch_members, primary_key: false) do
      add(:epoch_number, references(:shinerium_epochs, column: :number, type: :bigint, on_delete: :delete_all),
        null: false,
        primary_key: true
      )

      add(:index, :integer, null: false, primary_key: true)
      # the member's Ed25519 identity key, and its identity address
      add(:identity, :bytea, null: false)
      add(:ed_address_hash, :bytea, null: false)
      add(:coinbase_hash, :bytea, null: true)
      add(:pq_key_hash, :bytea, null: true)
      add(:location, :jsonb, null: true)
      # how many of the epoch's certificates it signed; null while the epoch runs
      add(:signed, :bigint, null: true)
      # why it left at the epoch's end (the node's Eviction constants), if it did
      add(:removal_reason, :smallint, null: true)

      timestamps(null: false, type: :utc_datetime_usec)
    end

    create(index(:shinerium_epoch_members, [:identity, :epoch_number]))
    create(index(:shinerium_epoch_members, [:ed_address_hash]))

    # One row for each identity the explorer has seen in a committee or among
    # the nodes joining one; the bond's fields from `shn_getValidator`, null
    # until the node serves it.
    create table(:shinerium_validators, primary_key: false) do
      add(:identity, :bytea, null: false, primary_key: true)
      add(:ed_address_hash, :bytea, null: false)
      add(:name, :string, null: true)
      add(:status, :string, null: true)
      add(:genesis, :boolean, null: true)
      add(:amount, :numeric, precision: 100, null: true)
      add(:bond_owner_hash, :bytea, null: true)
      add(:refund_address_hash, :bytea, null: true)
      add(:bls_hash, :bytea, null: true)
      add(:pq_hash, :bytea, null: true)
      add(:active_at, :bigint, null: true)
      add(:exiting, :boolean, null: true)
      add(:release_at, :utc_datetime_usec, null: true)
      add(:forced_exit, :boolean, null: true)
      add(:required, :numeric, precision: 100, null: true)
      add(:shortfall, :numeric, precision: 100, null: true)
      add(:penalty, :jsonb, null: true)
      add(:penalty_box, :jsonb, null: true)
      # the block shn_getValidator read the bond at
      add(:bond_block_number, :bigint, null: true)

      timestamps(null: false, type: :utc_datetime_usec)
    end

    create(unique_index(:shinerium_validators, [:ed_address_hash]))
  end
end
