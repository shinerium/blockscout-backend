# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Explorer.Repo.Shinerium.Migrations.AddShineriumEpochsJoinedSealNonce do
  use Ecto.Migration

  # The seal nonce of the control block that ends an epoch, whose candidate
  # joins the next committee (block-explorer-plan 11.30): it names the PoRC
  # generation, version and tier of the candidate's proof (the node's
  # blockseal/beaconhash/porc, SealNonce). Null when the control block seats no
  # candidate, and for the epochs stored before it was read.
  def change do
    alter table(:shinerium_epochs) do
      add(:joined_seal_nonce, :bigint, null: true)
    end
  end
end
