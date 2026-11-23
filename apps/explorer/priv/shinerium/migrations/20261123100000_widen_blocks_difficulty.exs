# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Explorer.Repo.Shinerium.Migrations.WidenBlocksDifficulty do
  use Ecto.Migration

  # The node's header difficulty grows by 1/2048 of its parent's for every block less
  # than ten seconds after it, Ethereum's Homestead adjustment, so under load it grows
  # without bound: on the test network the total difficulty passed 10^50, the limit of
  # Blockscout's numeric(50, 0), at block 211 454 on 23 November, and the import of
  # blocks stopped there for eight hours (block-explorer-plan 11.31). Unconstrained
  # numeric holds 131 072 digits, and Postgres widens the type without rewriting the
  # table.
  def change do
    alter table(:blocks) do
      modify(:difficulty, :numeric, from: {:numeric, precision: 50})
      modify(:total_difficulty, :numeric, from: {:numeric, precision: 50})
    end
  end
end
