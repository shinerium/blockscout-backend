# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule BlockScoutWeb.API.V2.ShineriumView do
  @moduledoc """
  Shinerium's own fields in the API v2 JSON: a `shinerium` object in blocks,
  transactions and withdrawals, from the fields the node serves (docs/eth-rpc.md
  of the node), and an account's post-quantum key and vesting
  (`/api/v2/shinerium/addresses/:address_hash_param`).
  """

  use Utils.CompileTimeEnvHelper, chain_type: [:explorer, :chain_type]

  alias Explorer.Chain.Shinerium.{Account, Epoch, EpochMember, Validator}
  alias Explorer.Chain.Wei

  # The node's post-quantum signature schemes, as crypto/pqsig of the node
  # names them, without its notes on which are reserved and which library
  # implements them. 0x20 is the test network's FN-DSA-512, from before FIPS 206.
  @pq_schemes %{
    0x00 => "none",
    0x10 => "ML-DSA-44",
    0x11 => "ML-DSA-65",
    0x20 => "FN-DSA-512 (pre-standard)",
    0x21 => "FN-DSA-512 (pre-standard, padded)",
    0x22 => "FN-DSA-1024 (pre-standard)",
    0x28 => "FN-DSA-512 (FIPS 206)",
    0x30 => "SLH-DSA"
  }

  @doc """
  The name of a post-quantum signature scheme, after the node's names. The
  numbers 0x01 to 0x0f belonged to a scheme library the node retired.
  """
  @spec pq_scheme_name(non_neg_integer() | nil) :: String.t() | nil
  def pq_scheme_name(nil), do: nil
  def pq_scheme_name(id) when id in 0x01..0x0F, do: "retired (0x#{hex_byte(id)})"
  def pq_scheme_name(id), do: Map.get(@pq_schemes, id, "unknown (0x#{hex_byte(id)})")

  defp hex_byte(id), do: id |> Integer.to_string(16) |> String.pad_leading(2, "0")

  defp pq_scheme(nil), do: nil
  defp pq_scheme(id), do: %{id: id, name: pq_scheme_name(id)}

  @doc """
  The JSON of `/api/v2/shinerium/addresses/:address_hash_param`: an account's
  post-quantum key and vesting (`Explorer.Chain.Shinerium.Account`), amounts in
  wei as strings and times in ISO 8601.
  """
  @spec account_json(Account.t()) :: map()
  def account_json(%{account_key: account_key, vesting: vesting}) do
    %{account_key: account_key_json(account_key), vesting: vesting_json(vesting)}
  end

  defp account_key_json(nil), do: nil
  defp account_key_json(account_key), do: %{account_key | scheme: pq_scheme(account_key.scheme)}

  defp vesting_json(nil), do: nil

  defp vesting_json(vesting) do
    %{
      vesting
      | locked: integer_string(vesting.locked),
        spendable: integer_string(vesting.spendable),
        vested: integer_string(vesting.vested),
        record: record_json(vesting.record)
    }
  end

  defp record_json(nil), do: nil
  defp record_json(record), do: %{record | amount: integer_string(record.amount)}

  defp integer_string(nil), do: nil
  defp integer_string(%Decimal{} = value), do: value |> Decimal.round(0) |> Decimal.to_integer() |> Integer.to_string()
  defp integer_string(%Wei{value: value}), do: integer_string(value)
  defp integer_string(value), do: Integer.to_string(value)

  defp integer(nil), do: nil
  defp integer(%Decimal{} = value), do: value |> Decimal.round(0) |> Decimal.to_integer()
  defp integer(value) when is_integer(value), do: value

  # The QC signature schemes of the node's bft/smartfhs (scheme.go).
  @qc_schemes %{0 => "none", 1 => "BLS", 2 => "ML-DSA", 3 => "hybrid (BLS and ML-DSA-44)"}

  @doc """
  An epoch in the list of epochs (`/api/v2/shinerium/epochs`); `current` is the
  number of the epoch that runs.
  """
  @spec epoch_json(Epoch.t() | map(), non_neg_integer() | nil) :: map()
  def epoch_json(%{epoch: %Epoch{} = epoch, signed: signed, removed: removed}, current) do
    ended? = not is_nil(epoch.ended_at)

    epoch
    |> epoch_json(current)
    |> Map.merge(%{signed: if(ended?, do: integer(signed) || 0), removed_count: if(ended?, do: removed || 0)})
  end

  def epoch_json(%Epoch{} = epoch, current) do
    %{
      number: epoch.number,
      control_block_hash: epoch.control_block_hash,
      committee_hash: epoch.committee_hash,
      started_at: epoch.started_at,
      ended_at: epoch.ended_at,
      carrier_block_number: epoch.carrier_block_number,
      first_block_number: Epoch.first_block_number(epoch),
      end_block_number: epoch.end_block_number,
      members_count: epoch.members_count,
      qcs: epoch.qcs,
      signed: nil,
      absent_kept: epoch.absent_kept,
      joined_count: epoch.joined && length(epoch.joined),
      removed_count: nil,
      is_current: epoch.number == current
    }
  end

  @doc """
  An epoch with its committee (`/api/v2/shinerium/epochs/:number`).
  """
  @spec epoch_detail_json(map(), non_neg_integer() | nil) :: map()
  def epoch_detail_json(%{epoch: epoch, members: members}, current) do
    ended? = not is_nil(epoch.ended_at)

    epoch
    |> epoch_json(current)
    |> Map.merge(%{
      signed: if(ended?, do: members |> Enum.map(&(&1.member.signed || 0)) |> Enum.sum()),
      removed_count: if(ended?, do: Enum.count(members, &(&1.member.removal_reason != nil))),
      next_first: epoch.next_first,
      members: Enum.map(members, &member_json(&1, epoch)),
      joined: epoch.joined && Enum.map(epoch.joined, &joined_json/1)
    })
  end

  defp member_json(%{member: member, name: name, reward: reward}, epoch) do
    %{
      index: member.index,
      identity: member.identity,
      ed_address_hash: member.ed_address_hash,
      name: name,
      coinbase_hash: member.coinbase_hash,
      pq_key_hash: member.pq_key_hash,
      location: member.location,
      signed: member.signed,
      correlated: member.correlated,
      credited: EpochMember.credited(member, epoch),
      slow: member.slow,
      removal: removal_json(member.removal_reason),
      reward: integer_string(reward)
    }
  end

  defp joined_json(node) do
    %{
      identity: prefixed(node["edPublic"]),
      ed_address_hash: node["edAddress"] && String.downcase(node["edAddress"]),
      coinbase_hash: node["coinbase"] && String.downcase(node["coinbase"]),
      pq_key_hash: prefixed(node["pqKeyHash"]),
      location: node["location"]
    }
  end

  defp prefixed(nil), do: nil
  defp prefixed("0x" <> _ = hex), do: String.downcase(hex)
  defp prefixed(hex), do: "0x" <> String.downcase(hex)

  defp removal_json(nil), do: nil
  defp removal_json(code), do: %{code: code, name: Epoch.removal_reason_name(code)}

  @doc """
  A validator in the list of validators (`/api/v2/shinerium/validators`).
  """
  @spec validator_json(map()) :: map()
  def validator_json(%{validator: %Validator{} = validator, stats: stats, rewards: rewards, member: member} = row) do
    stats = stats || %{}
    rewards = rewards || %{}
    location = Map.get(row, :location) || %{}

    %{
      identity: validator.identity,
      ed_address_hash: validator.ed_address_hash,
      name: validator.name,
      status: validator.status,
      genesis: validator.genesis,
      amount: integer_string(validator.amount),
      is_member: member,
      epochs: Map.get(stats, :epochs) || 0,
      first_epoch: Map.get(stats, :first_epoch),
      last_epoch: Map.get(stats, :last_epoch),
      signed: integer(Map.get(stats, :signed)),
      qcs: integer(Map.get(stats, :qcs)),
      rewards_total: integer_string(Map.get(rewards, :total)),
      rewards_count: Map.get(rewards, :count) || 0,
      location: Map.get(location, :location),
      location_epoch: Map.get(location, :epoch_number)
    }
  end

  @doc """
  A validator with its bond (`/api/v2/shinerium/validators/:id`).
  """
  @spec validator_detail_json(map()) :: map()
  def validator_detail_json(%{validator: %Validator{} = validator} = row) do
    row
    |> validator_json()
    |> Map.merge(%{
      bond_owner_hash: validator.bond_owner_hash,
      refund_address_hash: validator.refund_address_hash,
      bls_hash: validator.bls_hash,
      pq_hash: validator.pq_hash,
      active_at: validator.active_at,
      exiting: validator.exiting,
      release_at: validator.release_at,
      forced_exit: validator.forced_exit,
      required: integer_string(validator.required),
      shortfall: integer_string(validator.shortfall),
      penalty: validator.penalty,
      penalty_box: validator.penalty_box,
      bond_block_number: validator.bond_block_number
    })
  end

  @doc """
  An epoch a validator served (`/api/v2/shinerium/validators/:id/epochs`).
  """
  @spec validator_epoch_json(map()) :: map()
  def validator_epoch_json(%{member: member, epoch: epoch, reward: reward}) do
    %{
      epoch_number: member.epoch_number,
      index: member.index,
      started_at: epoch.started_at,
      ended_at: epoch.ended_at,
      signed: member.signed,
      qcs: if(member.signed, do: epoch.qcs),
      correlated: member.correlated,
      credited: EpochMember.credited(member, epoch),
      slow: member.slow,
      removal: removal_json(member.removal_reason),
      reward: integer_string(reward)
    }
  end

  @doc """
  A block's consensus (`/api/v2/shinerium/blocks/:block_hash_or_number_param/consensus`).
  """
  @spec block_consensus_json(map()) :: map()
  def block_consensus_json(%{epoch: epoch, view: view, justify: justify, certificate: certificate}) do
    %{epoch: epoch, view: view, justify: certificate_json(justify), certificate: certificate_json(certificate)}
  end

  defp certificate_json(nil), do: nil

  defp certificate_json(certificate) do
    by_index = Map.new(certificate.committee, &{&1.index, &1})

    %{
      certified_block_number: certificate.certified_block_number,
      certified_block_hash: certificate.certified_block_hash,
      carried_by_block_number: certificate.carried_by_block_number,
      carried_by_block_hash: certificate.carried_by_block_hash,
      epoch: certificate.epoch,
      view: certificate.view,
      scheme: %{id: certificate.scheme, name: Map.get(@qc_schemes, certificate.scheme)},
      committee_size: if(certificate.committee == [], do: nil, else: length(certificate.committee)),
      signers:
        Enum.map(certificate.signers, fn index ->
          member = Map.get(by_index, index, %{})

          %{
            index: index,
            identity: Map.get(member, :identity),
            ed_address_hash: Map.get(member, :ed_address_hash),
            name: Map.get(member, :name)
          }
        end)
    }
  end

  if @chain_type == :shinerium do
    alias Explorer.Chain.{Block, Hash, Transaction, Withdrawal}
    alias Explorer.Chain.Shinerium.SystemCall

    @doc """
    Adds a `shinerium` object to a block's JSON: the block's type (`"control"` for
    a carrier, the block that ends an epoch), its epoch's control block, the
    issue it pays the committee (a carrier's; zero in other blocks), the header's
    total supply after it, and its access list's hash. `poq_miner_hash` and
    `anchor_chain_hash` are null where the header holds zero.

    A block indexed before the chain type has no Shinerium fields; then every
    value is null.
    """
    @spec extend_block_json_response(map(), Block.t()) :: map()
    def extend_block_json_response(out_json, %Block{} = block) do
      Map.put(out_json, :shinerium, %{
        block_type: block.shn_block_type,
        control_block_number: block.shn_control_block_number,
        control_block_hash: block.shn_control_block_hash,
        reward: block.shn_reward,
        total_supply: block.shn_total_supply,
        block_access_list_hash: block.shn_block_access_list_hash,
        poq_miner_hash: nonzero(block.shn_poq_miner_hash),
        anchor_chain_hash: nonzero(block.shn_anchor_chain_hash),
        epoch: block.shn_epoch,
        view: block.shn_view,
        justify: justify_json(block)
      })
    end

    defp justify_json(%Block{shn_justify_signers: signers} = block) when is_list(signers) do
      %{
        epoch: block.shn_justify_epoch,
        view: block.shn_justify_view,
        scheme: block.shn_justify_scheme,
        signers_count: length(signers)
      }
    end

    defp justify_json(_block), do: nil

    @doc """
    Adds a `shinerium` object to a transaction's JSON: its version (1 for
    Shinerium's extended form), its form (`"extended"`, `"hybrid"` or
    `"envelope"`; null for Ethereum's forms), the post-quantum witness's scheme
    with its name, the post-quantum sender where the node names one, the
    metadata's hash, and the operation it asks of a system contract that takes
    RLP input (`Explorer.Chain.Shinerium.SystemCall`).

    A named operation is also the transaction's `method`, in place of the first
    four bytes of its RLP.
    """
    @spec extend_transaction_json_response(map(), Transaction.t()) :: map()
    def extend_transaction_json_response(out_json, %Transaction{} = transaction) do
      operation = SystemCall.decode(transaction.to_address_hash, transaction.input)

      out_json
      |> put_method(operation)
      |> Map.put(:shinerium, %{
        version: transaction.shn_version,
        form: transaction.shn_form,
        pq_scheme: pq_scheme(transaction.shn_pq_scheme),
        pq_sender_hash: transaction.shn_pq_sender_hash,
        metadata_hash: transaction.shn_metadata_hash,
        operation: operation_json(operation)
      })
    end

    defp put_method(out_json, %{name: name}) when is_binary(name), do: Map.put(out_json, "method", name)
    defp put_method(out_json, _operation), do: out_json

    defp operation_json(nil), do: nil

    defp operation_json(operation) do
      %{
        contract: operation.contract,
        code: operation.code,
        name: operation.name,
        identity: hex(operation.identity),
        proposal: operation.proposal,
        kind: operation.kind,
        choice: operation.choice,
        scheme: pq_scheme(operation.scheme),
        policy: operation.policy,
        binary: hex(operation.binary),
        version: operation.version
      }
    end

    defp hex(nil), do: nil
    defp hex(bytes), do: "0x" <> Base.encode16(bytes, case: :lower)

    @doc """
    Adds a `shinerium` object to a withdrawal's JSON: the reward's type
    (`"committee"`, `"poq"`, `"ecosystem"` or `"support"`) and, for a committee
    member's reward, the member's identity address. Each carrier pays its epoch's
    rewards; `validator_index` is the number of the epoch's control block.
    """
    @spec extend_withdrawal_json_response(map(), Withdrawal.t()) :: map()
    def extend_withdrawal_json_response(out_json, %Withdrawal{} = withdrawal) do
      Map.put(out_json, "shinerium", %{
        reward_type: withdrawal.shn_reward_type,
        validator_hash: withdrawal.shn_validator_hash
      })
    end

    defp nonzero(nil), do: nil

    defp nonzero(%Hash{bytes: bytes} = hash) do
      if bytes == <<0::size(byte_size(bytes) * 8)>>, do: nil, else: hash
    end
  else
    def extend_block_json_response(out_json, _), do: out_json
    def extend_transaction_json_response(out_json, _), do: out_json
    def extend_withdrawal_json_response(out_json, _), do: out_json
  end
end
