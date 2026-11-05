# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule BlockScoutWeb.API.V2.ShineriumView do
  @moduledoc """
  Shinerium's own fields in the API v2 JSON: a `shinerium` object in blocks,
  transactions and withdrawals, from the fields the node serves (docs/eth-rpc.md
  of the node).
  """

  use Utils.CompileTimeEnvHelper, chain_type: [:explorer, :chain_type]

  if @chain_type == :shinerium do
    alias Explorer.Chain.{Block, Hash, Transaction, Withdrawal}
    alias Explorer.Chain.Shinerium.SystemCall

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
        anchor_chain_hash: nonzero(block.shn_anchor_chain_hash)
      })
    end

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
