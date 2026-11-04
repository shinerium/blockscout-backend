# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Explorer.Chain.Supply.Shinerium do
  @moduledoc """
  The supply of a Shinerium chain: the header's `totalSupply` of the latest
  block, in SHN. The chain keeps it in every header: it grows at the carriers
  by the epoch's issue and falls by what is burned (the base fee, the airdrop's
  remainder at its close), so no sum of balances is needed.

  The circulating supply is the total for now: the vested and bonded parts are
  in the accounts' balances, and `shn_getVesting` gives an account's locked part.
  """

  use Explorer.Chain.Supply

  import Ecto.Query, only: [from: 2]

  alias Explorer.Chain.{Block, Wei}
  alias Explorer.Repo

  @wei_per_coin Decimal.new(1_000_000_000_000_000_000)

  def total do
    query =
      from(block in Block,
        where: block.consensus == true and not is_nil(block.shn_total_supply),
        order_by: [desc: block.number],
        limit: 1,
        select: block.shn_total_supply
      )

    case Repo.replica().one(query) do
      %Wei{value: value} -> Decimal.div(value, @wei_per_coin)
      _ -> nil
    end
  end

  def circulating, do: total()
end
