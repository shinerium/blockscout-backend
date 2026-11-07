# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Explorer.Repo.Shinerium.Migrations.AddShineriumCredited do
  use Ecto.Migration

  # What a control block's record says of each member besides its signatures
  # (block-explorer-plan 11.18), as `shn_getControlBlockByNumber` gives it from
  # the node's tree 0.2.1-2da5803b on: the correlated misses the carrier's
  # payment deducts, and the consecutive epochs that found a member slow.
  def change do
    alter table(:shinerium_epoch_members) do
      # the member's correlated misses in the epoch, from the record that ends
      # it; null on a network without the correlation penalty, or while unread
      add(:correlated, :bigint, null: true)
      # the consecutive epochs before this one that found the member slow, from
      # the record of the control block that seats the committee
      add(:slow, :integer, null: true)
    end

    alter table(:shinerium_epochs) do
      # whether the record that ends the epoch was read from a node that serves
      # `correlated` and `slow`; the fetcher reads the others again once it does
      add(:record_complete, :boolean, null: false, default: false)
    end
  end
end
