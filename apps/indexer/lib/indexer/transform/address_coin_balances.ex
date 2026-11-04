# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Indexer.Transform.AddressCoinBalances do
  @moduledoc """
  Extracts `Explorer.Chain.Address.CoinBalance` params from other schema's params.
  """

  use Utils.CompileTimeEnvHelper,
    chain_identity: [:explorer, :chain_identity],
    chain_type: [:explorer, :chain_type]

  use Utils.RuntimeEnvHelper,
    chain_type: [:explorer, :chain_type],
    arc_native_token_system_address: [:indexer, [:arc, :arc_native_token_system_address]]

  import Explorer.Helper, only: [truncate_address_hash: 1]
  import Explorer.Chain.SmartContract, only: [burn_address_hash_string: 0]

  @burn_address_hash_string burn_address_hash_string()

  alias Explorer.Chain.TokenTransfer

  def params_set(%{} = import_options) do
    Enum.reduce(import_options, MapSet.new(), &reducer/2)
  end

  defp reducer({:beneficiary_params, beneficiary_params}, acc) when is_list(beneficiary_params) do
    Enum.into(beneficiary_params, acc, fn %{address_hash: address_hash, block_number: block_number}
                                          when is_binary(address_hash) and is_integer(block_number) ->
      %{address_hash: address_hash, block_number: block_number}
    end)
  end

  defp reducer({:blocks_params, blocks_params}, acc) when is_list(blocks_params) do
    Enum.reduce(blocks_params, acc, &blocks_params_reducer/2)
  end

  defp reducer({:internal_transactions_params, internal_transactions_params}, initial)
       when is_list(internal_transactions_params) do
    Enum.reduce(internal_transactions_params, initial, &internal_transactions_params_reducer/2)
  end

  defp reducer({:logs_params, logs_params}, acc) when is_list(logs_params) do
    # a log MUST have address_hash and block_number
    filtered_logs =
      logs_params
      |> Enum.reject(
        &(&1.first_topic == TokenTransfer.constant() or
            &1.first_topic == TokenTransfer.erc1155_single_transfer_signature() or
            &1.first_topic == TokenTransfer.erc1155_batch_transfer_signature())
      )
      |> Enum.into(acc, fn
        %{address_hash: address_hash, block_number: block_number}
        when is_binary(address_hash) and is_integer(block_number) ->
          %{address_hash: address_hash, block_number: block_number}

        %{type: "pending"} ->
          nil
      end)
      |> Enum.reject(fn val -> is_nil(val) end)

    # for :arc chain type we also need to parse the `NativeCoinTransferred`, `NativeCoinMinted`, `NativeCoinBurned`, EIP-7708 events
    filtered_arc_logs =
      if chain_type() == :arc do
        handle_arc_transfer_logs(logs_params)
      else
        []
      end

    filtered_shinerium_logs =
      if chain_type() == :shinerium do
        handle_shinerium_system_logs(logs_params)
      else
        []
      end

    MapSet.new(filtered_logs ++ filtered_arc_logs ++ filtered_shinerium_logs)
  end

  defp reducer({:transactions_params, transactions_params}, initial) when is_list(transactions_params) do
    Enum.reduce(transactions_params, initial, &transactions_params_reducer/2)
  end

  defp reducer({:block_second_degree_relations_params, block_second_degree_relations_params}, initial)
       when is_list(block_second_degree_relations_params),
       do: initial

  defp reducer({:withdrawals, withdrawals}, acc) when is_list(withdrawals) do
    Enum.into(withdrawals, acc, fn %{address_hash: address_hash, block_number: block_number}
                                   when is_binary(address_hash) and is_integer(block_number) ->
      %{address_hash: address_hash, block_number: block_number}
    end)
  end

  # Shinerium's system contracts pay some accounts without a call, so that no
  # transaction or internal transaction names them (docs/system-events.md of the
  # node). Their events name them instead:
  # - `BondWithdrawn(bytes32 indexed identity, address indexed withdrawal, uint256)`
  #   at the bond contract: the bond goes to `withdrawal`;
  # - `AirdropClaimed(address indexed account, address indexed recipient, uint256)`
  #   at the claim contract: the claim goes to `recipient` (a relayed claim's
  #   recipient is neither the sender nor a callee);
  # - `VestingGranted(address indexed grantor, address indexed recipient, uint256)`
  #   at VESTING: a grant moves coins from the pool to `recipient`;
  # - `ProposalExecuted(uint64 indexed proposal, uint8, uint64 account, bytes32 target, uint256)`
  #   at the council: a transfer pays `target` from the treasury account
  #   `0x…0110 + account`.
  # The contract itself is in the log's `address_hash`, which the clause above
  # takes already.
  @shinerium_bond_contract "0x0000000000000000000000000000000000000102"
  @shinerium_council_contract "0x0000000000000000000000000000000000000107"
  @shinerium_vesting_contract "0x0000000000000000000000000000000000000108"
  @shinerium_airdrop_claim_contract "0x0000000000000000000000000000000000000109"
  @shinerium_bond_withdrawn "0x25ea4793db0032b8cdaaca90cfb1a94c62132a3aa5194c98958659c26fe2672e"
  @shinerium_airdrop_claimed "0xb0a0840c7bb9b6ecca130f40e5b8f2158da27eb5c5c9432c8f424a520c8b55d1"
  @shinerium_vesting_granted "0xca5c5afc14d369678cb16f3b1b1298dd0162d0597efcb41f8b542cc0ce5d7632"
  @shinerium_proposal_executed "0xedd1a0f1ef31b9496b9bfa3b748ea44fb91da8dc93cc45ea3b0b88989b7b0600"
  @shinerium_council_account_base 0x0110

  @doc false
  @spec shinerium_system_event_topics() :: %{atom() => String.t()}
  def shinerium_system_event_topics do
    %{
      bond_withdrawn: @shinerium_bond_withdrawn,
      airdrop_claimed: @shinerium_airdrop_claimed,
      vesting_granted: @shinerium_vesting_granted,
      proposal_executed: @shinerium_proposal_executed
    }
  end

  @spec handle_shinerium_system_logs([map()]) :: [%{:address_hash => String.t(), :block_number => non_neg_integer()}]
  defp handle_shinerium_system_logs(logs_params) do
    logs_params
    |> Enum.flat_map(fn
      %{type: "pending"} ->
        []

      %{block_number: block_number} = log when is_integer(block_number) ->
        log
        |> shinerium_paid_addresses()
        |> Enum.map(&%{address_hash: &1, block_number: block_number})

      _ ->
        []
    end)
  end

  defp shinerium_paid_addresses(log) do
    address = log |> Map.get(:address_hash) |> to_string() |> String.downcase()
    first_topic = log |> Map.get(:first_topic) |> downcase_or_nil()

    case {address, first_topic} do
      {@shinerium_bond_contract, @shinerium_bond_withdrawn} ->
        topic_addresses(log, [:third_topic])

      {@shinerium_airdrop_claim_contract, @shinerium_airdrop_claimed} ->
        topic_addresses(log, [:third_topic])

      {@shinerium_vesting_contract, @shinerium_vesting_granted} ->
        topic_addresses(log, [:second_topic, :third_topic])

      {@shinerium_council_contract, @shinerium_proposal_executed} ->
        council_transfer_addresses(Map.get(log, :data))

      _ ->
        []
    end
  end

  defp topic_addresses(log, keys) do
    keys
    |> Enum.map(&Map.get(log, &1))
    |> Enum.filter(&is_binary/1)
    |> Enum.map(&truncate_address_hash/1)
  end

  # The data of ProposalExecuted: kind, account, target and amount, a word each.
  # A target whose first 12 bytes are zero and the rest not is an address.
  defp council_transfer_addresses(data) do
    with true <- is_binary(data) or is_struct(data),
         "0x" <> hex <- data |> to_string() |> String.downcase(),
         {:ok, <<_kind::binary-size(32), account::unsigned-big-integer-size(256), target::binary-size(32), _::binary>>} <-
           Base.decode16(hex, case: :lower) do
      account_address =
        if account < 0x10,
          do: [address_from_integer(@shinerium_council_account_base + account)],
          else: []

      target_address =
        case target do
          <<0::size(96), 0::size(160)>> -> []
          <<0::size(96), recipient::binary-size(20)>> -> ["0x" <> Base.encode16(recipient, case: :lower)]
          _ -> []
        end

      account_address ++ target_address
    else
      _ -> []
    end
  end

  defp address_from_integer(integer) do
    "0x" <> Base.encode16(<<integer::unsigned-big-integer-size(160)>>, case: :lower)
  end

  defp downcase_or_nil(nil), do: nil
  defp downcase_or_nil(value), do: value |> to_string() |> String.downcase()

  # Handles Arc chain type logs.
  #
  # ## Parameters
  # - `logs_params`: The given list of logs.
  #
  # ## Returns
  # - The list of `address_hash, block_number` pairs.
  @spec handle_arc_transfer_logs([
          %{
            :first_topic => String.t(),
            :second_topic => String.t(),
            :third_topic => String.t() | nil,
            :address_hash => String.t(),
            :block_number => non_neg_integer(),
            optional(:type) => String.t() | nil
          }
        ]) :: [%{:address_hash => String.t(), :block_number => non_neg_integer()}]
  defp handle_arc_transfer_logs(logs_params) do
    arc_native_coin_transferred_event = TokenTransfer.arc_native_coin_transferred_event()
    arc_native_coin_minted_event = TokenTransfer.arc_native_coin_minted_event()
    arc_native_coin_burned_event = TokenTransfer.arc_native_coin_burned_event()
    arc_native_token_system_address = arc_native_token_system_address()
    eip7708_transfer_topic = TokenTransfer.constant()
    eip7708_system_address = TokenTransfer.eip7708_system_address()

    logs_params
    |> Enum.flat_map(fn
      %{
        type: "pending"
      } ->
        []

      %{
        first_topic: ^eip7708_transfer_topic,
        second_topic: second_topic,
        third_topic: third_topic,
        address_hash: ^eip7708_system_address,
        block_number: block_number
      }
      when is_integer(block_number) and is_binary(second_topic) and is_binary(third_topic) ->
        [
          %{address_hash: truncate_address_hash(second_topic), block_number: block_number},
          %{address_hash: truncate_address_hash(third_topic), block_number: block_number}
        ]
        |> Enum.filter(fn %{address_hash: address_hash} -> address_hash != @burn_address_hash_string end)

      %{
        first_topic: ^arc_native_coin_transferred_event,
        second_topic: second_topic,
        third_topic: third_topic,
        address_hash: ^arc_native_token_system_address,
        block_number: block_number
      }
      when is_integer(block_number) ->
        [
          %{address_hash: truncate_address_hash(second_topic), block_number: block_number},
          %{address_hash: truncate_address_hash(third_topic), block_number: block_number}
        ]

      %{
        first_topic: ^arc_native_coin_minted_event,
        second_topic: second_topic,
        address_hash: ^arc_native_token_system_address,
        block_number: block_number
      }
      when is_integer(block_number) ->
        [%{address_hash: truncate_address_hash(second_topic), block_number: block_number}]

      %{
        first_topic: ^arc_native_coin_burned_event,
        second_topic: second_topic,
        address_hash: ^arc_native_token_system_address,
        block_number: block_number
      }
      when is_integer(block_number) ->
        [%{address_hash: truncate_address_hash(second_topic), block_number: block_number}]

      _ ->
        []
    end)
  end

  defp blocks_params_reducer(%{miner_hash: address_hash, number: block_number}, acc)
       when is_binary(address_hash) and is_integer(block_number) do
    MapSet.put(acc, %{address_hash: address_hash, block_number: block_number})
  end

  defp blocks_params_reducer(_block_params, acc), do: acc

  defp internal_transactions_params_reducer(%{block_number: block_number} = internal_transaction_params, acc)
       when is_integer(block_number) do
    case internal_transaction_params do
      %{error: _} ->
        acc

      %{type: "call", call_type: call_type, value: value} = params when call_type in ~w(call invalid) and value > 0 ->
        acc
        |> process_internal_transaction_field(params, :from_address_hash, block_number)
        |> process_internal_transaction_field(params, :to_address_hash, block_number)

      %{type: type} = params when type in ~w(create create2) ->
        acc
        |> process_internal_transaction_field(params, :from_address_hash, block_number)
        |> process_internal_transaction_field(params, :created_contract_address_hash, block_number)

      %{type: "selfdestruct", from_address_hash: from_address_hash, to_address_hash: to_address_hash}
      when is_binary(from_address_hash) and is_binary(to_address_hash) ->
        acc
        |> MapSet.put(%{address_hash: from_address_hash, block_number: block_number})
        |> MapSet.put(%{address_hash: to_address_hash, block_number: block_number})

      _params ->
        acc
    end
  end

  defp process_internal_transaction_field(acc, params, field, block_number) do
    case Map.get(params, field) do
      nil -> acc
      address_hash -> MapSet.put(acc, %{address_hash: address_hash, block_number: block_number})
    end
  end

  defp transactions_params_reducer(
         %{block_number: block_number, from_address_hash: from_address_hash} = transaction_params,
         initial
       )
       when is_integer(block_number) and is_binary(from_address_hash) do
    # a transaction MUST have a `from_address_hash`
    initial
    |> MapSet.put(%{address_hash: from_address_hash, block_number: block_number})
    |> (&(case transaction_params do
            %{to_address_hash: to_address_hash} when is_binary(to_address_hash) ->
              MapSet.put(&1, %{address_hash: to_address_hash, block_number: block_number})

            _ ->
              &1
          end)).()
    |> (&transactions_params_chain_type_fields_reducer(transaction_params, &1)).()
  end

  if @chain_identity == {:optimism, :celo} do
    # todo: subject for deprecation, since celo transactions with
    # gatewayFeeRecipient are deprecated
    defp transactions_params_chain_type_fields_reducer(
           %{
             block_number: block_number,
             gas_fee_recipient_address_hash: recipient_address_hash,
             gas_token_contract_address_hash: nil
           },
           initial
         )
         when is_integer(block_number) and
                is_binary(recipient_address_hash) and
                recipient_address_hash != @burn_address_hash_string do
      MapSet.put(initial, %{address_hash: recipient_address_hash, block_number: block_number})
    end
  end

  if @chain_type == :eden do
    defp transactions_params_chain_type_fields_reducer(
           %{block_number: block_number} = transaction_params,
           initial
         )
         when is_integer(block_number) do
      initial
      |> put_fee_payer(transaction_params, block_number)
      |> put_calls_recipients(transaction_params, block_number)
    end
  end

  defp transactions_params_chain_type_fields_reducer(_, acc), do: acc

  if @chain_type == :eden do
    alias Explorer.Chain

    defp put_fee_payer(acc, %{fee_payer_address_hash: fee_payer_address_hash}, block_number)
         when is_binary(fee_payer_address_hash) do
      MapSet.put(acc, %{address_hash: fee_payer_address_hash, block_number: block_number})
    end

    defp put_fee_payer(acc, _transaction_params, _block_number), do: acc

    defp put_calls_recipients(acc, %{calls: calls}, block_number) when is_list(calls) do
      Enum.reduce(calls, acc, fn call, inner_acc ->
        address_hash = Map.get(call, "to")

        case Chain.string_to_address_hash(address_hash) do
          {:ok, _} -> MapSet.put(inner_acc, %{address_hash: address_hash, block_number: block_number})
          :error -> inner_acc
        end
      end)
    end

    defp put_calls_recipients(acc, _transaction_params, _block_number), do: acc
  end
end
