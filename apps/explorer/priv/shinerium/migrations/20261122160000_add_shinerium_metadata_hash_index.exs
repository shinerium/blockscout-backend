# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Explorer.Repo.Shinerium.Migrations.AddShineriumMetadataHashIndex do
  use Ecto.Migration

  @disable_ddl_transaction true
  @disable_migration_lock true

  # The transactions that carry a metadata hash, the newest first, for the hash's
  # page (`/api/v2/shinerium/metadata/:metadata_hash_param`). Most transactions
  # carry none, so the index holds only those that do; it is built concurrently, as
  # the table may be large.
  def change do
    create_if_not_exists(
      index(:transactions, [:shn_metadata_hash, :block_number, :index],
        name: :transactions_shn_metadata_hash_index,
        where: "shn_metadata_hash IS NOT NULL",
        concurrently: true
      )
    )
  end
end
