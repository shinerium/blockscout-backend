# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Explorer.Repo.Shinerium.Migrations.AddShineriumFields do
  use Ecto.Migration

  # Shinerium's own fields of blocks, transactions and withdrawals, as the node
  # serves them in eth_getBlockByNumber (docs/eth-rpc.md of the node).
  def change do
    alter table(:blocks) do
      # "normal", or "control" for a carrier, the block that ends an epoch
      add(:shn_block_type, :string, null: true)
      add(:shn_control_block_number, :bigint, null: true)
      add(:shn_control_block_hash, :bytea, null: true)
      # the issue a carrier pays out to the committee, in wei; zero in other blocks
      add(:shn_reward, :numeric, precision: 100, null: true)
      # the header's total supply after the block, in wei
      add(:shn_total_supply, :numeric, precision: 100, null: true)
      add(:shn_block_access_list_hash, :bytea, null: true)
      add(:shn_poq_miner_hash, :bytea, null: true)
      add(:shn_anchor_chain_hash, :bytea, null: true)
    end

    alter table(:transactions) do
      # 0 for Ethereum's forms, 1 for Shinerium's extended form
      add(:shn_version, :smallint, null: true)
      # "extended", "hybrid" or "envelope"; null for Ethereum's forms
      add(:shn_form, :string, null: true)
      add(:shn_pq_sender_hash, :bytea, null: true)
      # the post-quantum witness's scheme (crypto/pqsig ID of the node)
      add(:shn_pq_scheme, :smallint, null: true)
      add(:shn_metadata_hash, :bytea, null: true)
    end

    alter table(:withdrawals) do
      # "committee", "poq", "ecosystem" or "support"
      add(:shn_reward_type, :string, null: true)
      # the identity address of the committee member a "committee" reward pays
      add(:shn_validator_hash, :bytea, null: true)
    end
  end
end
