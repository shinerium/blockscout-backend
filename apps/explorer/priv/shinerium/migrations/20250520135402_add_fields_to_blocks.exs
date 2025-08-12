defmodule Explorer.Repo.Shinerium.Migrations.AddShnFieldsToBlocks do
  use Ecto.Migration

  # SHN shinerium block fields
  def change do
    alter table(:blocks) do
      add(:block_type, :decimal)
      add(:key_hash, :bytea)
      add(:key_number, :decimal)
      add(:pow_miner, :bytea)
      add(:reward, :decimal)
      add(:tx_count, :decimal)
      add(:withdrawals_root, :bytea)
      add(:anchor_chain_hash, :bytea)
      add(:withdrawal_base_index, :decimal)
    end
  end
end
