# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Explorer.Chain.Shinerium.Consensus do
  @moduledoc """
  Reads and writes the Shinerium chain's epochs, committees and validators
  (block-explorer-plan 6.1, stage B): what `Indexer.Fetcher.Shinerium.Epochs`
  stores, and what the API's `/api/v2/shinerium` endpoints show.

  An epoch's rewards are the carrier's withdrawals of the type `committee` that
  name the epoch in `validator_index` (FHS-155: the carrier that ends epoch N
  pays N's committee); a member's is the one whose `shn_validator_hash` is its
  identity address.
  """

  import Ecto.Query

  alias Explorer.Chain.{Block, Hash, Withdrawal}
  alias Explorer.Chain.Shinerium.{Epoch, EpochMember, Validator}
  alias Explorer.{PagingOptions, Repo}

  @epoch_fields ~w(control_block_hash committee_hash started_at carrier_block_number members_count ended_at
                   end_block_number qcs absent_kept next_first joined updated_at)a
  @member_fields ~w(identity ed_address_hash coinbase_hash pq_key_hash location signed removal_reason updated_at)a

  @doc """
  Stores epochs and their committees, each epoch with all its members, replacing
  what was stored of them: a running epoch is written again once it ends.
  """
  @spec import_epochs([map()], [map()]) :: {:ok, any()} | {:error, any()}
  def import_epochs([], _members), do: {:ok, :nothing}

  def import_epochs(epochs, members) do
    now = DateTime.utc_now()
    stamp = &Map.merge(&1, %{inserted_at: now, updated_at: now})

    Repo.transaction(fn ->
      {_, _} =
        Repo.insert_all(Epoch, Enum.map(epochs, stamp),
          on_conflict: {:replace, @epoch_fields},
          conflict_target: [:number]
        )

      members
      |> Enum.map(stamp)
      |> Enum.chunk_every(1_000)
      |> Enum.each(fn chunk ->
        Repo.insert_all(EpochMember, chunk,
          on_conflict: {:replace, @member_fields},
          conflict_target: [:epoch_number, :index]
        )
      end)
    end)
  end

  @doc """
  Stores validators: a new identity with what is known of it, and for a known
  one only the fields given (the bond's, once the node has been asked).
  """
  @spec upsert_validators([map()]) :: {non_neg_integer(), nil}
  def upsert_validators([]), do: {0, nil}

  def upsert_validators(rows) do
    now = DateTime.utc_now()

    rows
    |> Enum.group_by(&Map.keys/1)
    |> Enum.reduce({0, nil}, fn {keys, group}, {count, _} ->
      replace = (keys -- [:identity]) ++ [:updated_at]
      entries = Enum.map(group, &Map.merge(&1, %{inserted_at: now, updated_at: now}))
      {n, _} = Repo.insert_all(Validator, entries, on_conflict: {:replace, replace}, conflict_target: [:identity])
      {count + n, nil}
    end)
  end

  @doc "The highest epoch whose end is stored, or nil."
  @spec last_ended_epoch() :: non_neg_integer() | nil
  def last_ended_epoch do
    Repo.one(from(e in Epoch, where: not is_nil(e.ended_at), select: max(e.number)))
  end

  @doc "The identities of the validators, the ones read longest ago first."
  @spec validator_identities(non_neg_integer()) :: [Hash.Full.t()]
  def validator_identities(limit) do
    Repo.all(
      from(v in Validator,
        order_by: [asc_nulls_first: v.bond_block_number, asc: v.updated_at],
        limit: ^limit,
        select: v.identity
      )
    )
  end

  @doc """
  Epochs, the newest first, `paging_options.key` an epoch number to continue below.
  """
  @spec epochs(PagingOptions.t()) :: [%{epoch: Epoch.t(), signed: Decimal.t() | nil, removed: non_neg_integer()}]
  def epochs(%PagingOptions{key: key, page_size: page_size}) do
    totals =
      from(m in EpochMember,
        group_by: m.epoch_number,
        select: %{epoch_number: m.epoch_number, signed: sum(m.signed), removed: count(m.removal_reason)}
      )

    query =
      from(e in Epoch,
        left_join: t in subquery(totals),
        on: t.epoch_number == e.number,
        order_by: [desc: e.number],
        limit: ^page_size,
        select: %{epoch: e, signed: t.signed, removed: t.removed}
      )

    query =
      case key do
        %{number: number} -> where(query, [e], e.number < ^number)
        _ -> query
      end

    Repo.all(query)
  end

  @doc "The number of the epoch that runs now, or nil."
  @spec current_epoch_number() :: non_neg_integer() | nil
  def current_epoch_number do
    Repo.one(from(e in Epoch, select: max(e.number)))
  end

  @doc """
  An epoch with its committee in committee order, each member with its
  validator's name and its reward for the epoch.
  """
  @spec epoch(non_neg_integer()) :: {:ok, map()} | {:error, :not_found}
  def epoch(number) do
    case Repo.get(Epoch, number) do
      nil ->
        {:error, :not_found}

      epoch ->
        members =
          Repo.all(
            from(m in EpochMember,
              left_join: v in Validator,
              on: v.identity == m.identity,
              where: m.epoch_number == ^number,
              order_by: [asc: m.index],
              select: {m, v.name}
            )
          )

        rewards = committee_rewards(number)

        {:ok,
         %{
           epoch: epoch,
           members:
             Enum.map(members, fn {member, name} ->
               %{member: member, name: name, reward: Map.get(rewards, member.ed_address_hash)}
             end)
         }}
    end
  end

  defp committee_rewards(epoch_number) do
    from(w in Withdrawal,
      where: w.validator_index == ^epoch_number and w.shn_reward_type == "committee",
      select: {w.shn_validator_hash, w.amount}
    )
    |> Repo.all()
    |> Map.new()
  end

  @doc """
  The validators, with what their committees say of them: the epochs they
  served, the certificates of their ended epochs and how many they signed, the
  rewards, and whether they sit in the epoch that runs now. Members first, then
  by epochs served.
  """
  @spec validators(non_neg_integer()) :: [map()]
  def validators(limit \\ 1_000) do
    current = current_epoch_number()

    stats =
      from(m in EpochMember,
        join: e in Epoch,
        on: e.number == m.epoch_number,
        group_by: m.identity,
        select: %{
          identity: m.identity,
          epochs: count(m.epoch_number),
          first_epoch: min(m.epoch_number),
          last_epoch: max(m.epoch_number),
          signed: sum(m.signed),
          qcs: sum(fragment("CASE WHEN ? IS NULL THEN NULL ELSE ? END", m.signed, e.qcs))
        }
      )

    rewards =
      from(w in Withdrawal,
        where: w.shn_reward_type == "committee",
        group_by: w.shn_validator_hash,
        select: %{ed_address_hash: w.shn_validator_hash, total: sum(w.amount), count: count(w.index)}
      )

    from(v in Validator,
      left_join: s in subquery(stats),
      on: s.identity == v.identity,
      left_join: r in subquery(rewards),
      on: r.ed_address_hash == v.ed_address_hash,
      order_by: [
        desc: fragment("COALESCE(? = ?, false)", s.last_epoch, ^(current || -1)),
        desc_nulls_last: s.epochs,
        asc: v.identity
      ],
      limit: ^limit,
      select: %{validator: v, stats: s, rewards: r}
    )
    |> Repo.all()
    |> Enum.map(&with_membership(&1, current))
  end

  defp with_membership(%{stats: stats} = row, current) do
    Map.put(row, :member, not is_nil(current) and not is_nil(stats) and stats.last_epoch == current)
  end

  @doc """
  A validator by its identity (32 bytes) or its identity address (20 bytes),
  with the same figures as `validators/1`.
  """
  @spec validator(binary()) :: {:ok, map()} | {:error, :not_found}
  def validator(id_bytes) when byte_size(id_bytes) in [20, 32] do
    query =
      if byte_size(id_bytes) == 32,
        do: from(v in Validator, where: v.identity == ^id_bytes),
        else: from(v in Validator, where: v.ed_address_hash == ^id_bytes)

    case Repo.one(query) do
      nil -> {:error, :not_found}
      validator -> {:ok, validator_figures(validator)}
    end
  end

  def validator(_), do: {:error, :not_found}

  defp validator_figures(%Validator{identity: identity, ed_address_hash: ed_address_hash} = validator) do
    current = current_epoch_number()

    stats =
      Repo.one(
        from(m in EpochMember,
          join: e in Epoch,
          on: e.number == m.epoch_number,
          where: m.identity == ^identity,
          select: %{
            epochs: count(m.epoch_number),
            first_epoch: min(m.epoch_number),
            last_epoch: max(m.epoch_number),
            signed: sum(m.signed),
            qcs: sum(fragment("CASE WHEN ? IS NULL THEN NULL ELSE ? END", m.signed, e.qcs))
          }
        )
      )

    rewards =
      Repo.one(
        from(w in Withdrawal,
          where: w.shn_reward_type == "committee" and w.shn_validator_hash == ^ed_address_hash,
          select: %{total: sum(w.amount), count: count(w.index)}
        )
      )

    stats = if stats && stats.epochs > 0, do: stats
    with_membership(%{validator: validator, stats: stats, rewards: rewards}, current)
  end

  @doc """
  The epochs a validator served, the newest first, each with its seat, the
  certificates it signed, why it left and its reward.
  """
  @spec validator_epochs(Hash.Full.t(), Hash.Address.t(), PagingOptions.t()) :: [map()]
  def validator_epochs(identity, ed_address_hash, %PagingOptions{key: key, page_size: page_size}) do
    query =
      from(m in EpochMember,
        join: e in Epoch,
        on: e.number == m.epoch_number,
        left_join: w in Withdrawal,
        on:
          w.validator_index == m.epoch_number and w.shn_reward_type == "committee" and
            w.shn_validator_hash == ^ed_address_hash,
        where: m.identity == ^identity,
        order_by: [desc: m.epoch_number],
        limit: ^page_size,
        select: %{member: m, epoch: e, reward: w.amount}
      )

    query =
      case key do
        %{number: number} -> where(query, [m], m.epoch_number < ^number)
        _ -> query
      end

    Repo.all(query)
  end

  @doc """
  A block's consensus: its epoch and view, the certificate of its parent that it
  carries (`justify`), and its own certificate, which its child carries; each
  certificate's signers named by the epoch's committee.
  """
  @spec block_consensus(Block.t()) :: map()
  def block_consensus(%Block{hash: hash, parent_hash: parent_hash, number: number} = block) do
    # The chain type's fields, read with Map.get: the module is compiled for
    # every chain type, and these exist only in Shinerium's.
    get = &Map.get(block, &1)

    child =
      Repo.one(
        from(b in Block,
          where: b.parent_hash == ^hash and b.consensus == true,
          select: %{
            carried_by_block_number: b.number,
            carried_by_block_hash: b.hash,
            epoch: field(b, :shn_justify_epoch),
            view: field(b, :shn_justify_view),
            scheme: field(b, :shn_justify_scheme),
            signers: field(b, :shn_justify_signers)
          }
        )
      )

    justify =
      if get.(:shn_justify_signers) do
        %{
          certified_block_number: number - 1,
          certified_block_hash: parent_hash,
          carried_by_block_number: number,
          carried_by_block_hash: hash,
          epoch: get.(:shn_justify_epoch),
          view: get.(:shn_justify_view),
          scheme: get.(:shn_justify_scheme),
          signers: get.(:shn_justify_signers)
        }
      end

    certificate =
      if child && child.signers,
        do: Map.merge(child, %{certified_block_number: number, certified_block_hash: hash})

    %{
      epoch: get.(:shn_epoch),
      view: get.(:shn_view),
      justify: name_signers(justify),
      certificate: name_signers(certificate)
    }
  end

  defp name_signers(nil), do: nil
  defp name_signers(%{epoch: nil} = qc), do: Map.put(qc, :committee, [])

  defp name_signers(%{epoch: epoch} = qc) do
    committee =
      Repo.all(
        from(m in EpochMember,
          left_join: v in Validator,
          on: v.identity == m.identity,
          where: m.epoch_number == ^epoch,
          order_by: [asc: m.index],
          select: %{index: m.index, identity: m.identity, ed_address_hash: m.ed_address_hash, name: v.name}
        )
      )

    Map.put(qc, :committee, committee)
  end
end
