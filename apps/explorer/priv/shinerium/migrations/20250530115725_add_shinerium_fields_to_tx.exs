defmodule Explorer.Repo.Shinerium.Migrations.AddShineriumFieldsToTx do
  use Ecto.Migration

  def change do
    alter table(:transactions) do
        add(:version, :decimal)
        add(:shn_metadata_hash, :bytea)
    end
  end
end
