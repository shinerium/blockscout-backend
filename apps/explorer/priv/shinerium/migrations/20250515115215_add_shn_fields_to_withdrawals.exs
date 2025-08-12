defmodule Explorer.Repo.Shinerium.Migrations.AddShnFieldsToWithdrawals do
  use Ecto.Migration
#
# SHN additional fields to withdrawals
#
  def change do
    alter table(:withdrawals) do
      add :reward_type, :integer
      add :validator, :bytea
    end
  end
end
