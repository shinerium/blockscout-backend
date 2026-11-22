# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Explorer.Chain.Shinerium.Metadata do
  @moduledoc """
  The metadata of Shinerium's extended transactions, by its hash (`shnMetadataHash`):
  the transactions that carry the hash, and the fields that it commits to, as the
  node gives them in a transaction's JSON (`metadata`, `identity`, `security` and
  `iso20022`; the node's `core/protocol/tx_meta.go` and `docs/reference/eth-rpc.md`).

  The hash is the Keccak-256 of the fields' RLP, and the node refuses a transaction
  whose hash is not that of its fields, so every transaction that carries one hash
  carries the same fields. Only the hash is indexed (`transactions.shn_metadata_hash`);
  the fields are read from the node, from the first transaction that carries them,
  when they are asked for.
  """

  import Ecto.Query, only: [from: 2, where: 3]

  require Logger

  alias Explorer.Chain
  alias Explorer.Chain.{Hash, Transaction}

  @type part :: %{optional(atom()) => String.t() | nil} | nil

  @type first_transaction :: %{
          hash: Hash.Full.t(),
          block_number: non_neg_integer() | nil,
          block_timestamp: DateTime.t() | nil
        }

  @type t :: %{
          metadata_hash: Hash.Full.t(),
          transactions_count: pos_integer(),
          first_transaction: first_transaction(),
          read_from_node: boolean(),
          metadata: part(),
          identity: part(),
          security: part(),
          iso20022: part()
        }

  # Each part's fields, in the order of the node's structs: the API's name, then
  # the node's JSON name. `hash_proof_text` of the security part is left out: the
  # node does not encode it (`rlp:"-"`), so no transaction on the chain has it.
  @parts [
    metadata: [
      ipfs: "ipfs",
      url: "url",
      note: "note",
      device_id: "deviceID",
      server: "server",
      off_chain_key: "off_chain_key",
      location: "location",
      origin_app: "origin_app",
      source_system: "source_system"
    ],
    identity: [
      type: "type",
      did: "did",
      vc: "vc",
      biometric_hash: "biometric_hash",
      id_proof_cid: "id_proof_cid"
    ],
    security: [
      hash_proof: "hash_proof",
      pub_key_proof: "pub_key_proof",
      encryption_key: "encryptionKey",
      verification_key: "verificationKey",
      attestation: "attestation"
    ],
    iso20022: [
      type: "type",
      tx_type: "txType",
      msg_id: "msg_id",
      reference: "reference",
      creditor_hash: "creditor_hash"
    ]
  ]

  @doc """
  The fields of each part, the API's names in the node's order.
  """
  @spec fields() :: keyword([atom()])
  def fields, do: Enum.map(@parts, fn {part, fields} -> {part, Keyword.keys(fields)} end)

  @doc """
  The metadata that `metadata_hash` commits to, with the number of transactions
  that carry it and the first of them. `{:error, :not_found}` when no indexed
  transaction carries it. When the node does not give the fields,
  `read_from_node` is false and every part is nil; a part the transaction does
  not have is nil.
  """
  @spec fetch(Hash.Full.t(), keyword()) :: {:ok, t()} | {:error, :not_found}
  def fetch(%Hash{} = metadata_hash, options \\ []) do
    repo = Chain.select_repo(options)

    first =
      repo.one(
        from(transaction in Transaction,
          where: transaction.shn_metadata_hash == ^metadata_hash,
          order_by: [asc: transaction.block_number, asc: transaction.index],
          limit: 1,
          select: %{
            hash: transaction.hash,
            block_number: transaction.block_number,
            block_timestamp: transaction.block_timestamp
          }
        )
      )

    case first do
      nil ->
        {:error, :not_found}

      first ->
        count =
          repo.aggregate(
            from(transaction in Transaction, where: transaction.shn_metadata_hash == ^metadata_hash),
            :count
          )

        parts = read_parts(first.hash, metadata_hash)

        {:ok,
         Map.merge(
           %{
             metadata_hash: metadata_hash,
             transactions_count: count,
             first_transaction: first,
             read_from_node: not is_nil(parts)
           },
           parts || Map.new(@parts, fn {part, _} -> {part, nil} end)
         )}
    end
  end

  @doc """
  The transactions that carry `metadata_hash`, the newest first, with the
  `:paging_options` (a key of `{block_number, index}`) and
  `:necessity_by_association` of a transaction list.
  """
  @spec transactions(Hash.Full.t(), keyword()) :: [Transaction.t()]
  def transactions(%Hash{} = metadata_hash, options \\ []) do
    paging_options = Keyword.get(options, :paging_options, Chain.default_paging_options())
    necessity_by_association = Keyword.get(options, :necessity_by_association, %{})

    paging_options
    |> Transaction.fetch_transactions()
    |> where([transaction], transaction.shn_metadata_hash == ^metadata_hash)
    |> Chain.join_associations(necessity_by_association)
    |> Transaction.put_has_token_transfers_to_transaction(false)
    |> Chain.select_repo(options).all()
  end

  @doc """
  The parts of a transaction's JSON as the node gives it (`eth_getTransactionByHash`):
  for each part a map of its fields, a field the transaction does not have nil, and
  nil for a part it does not have. Only strings are taken; a field of another kind
  is nil.
  """
  @spec parts(map()) :: %{atom() => part()}
  def parts(%{} = transaction_json) do
    Map.new(@parts, fn {part, fields} ->
      {part, transaction_json |> Map.get(Atom.to_string(part)) |> part(fields)}
    end)
  end

  defp part(%{} = json, fields), do: Map.new(fields, fn {name, node_name} -> {name, field(json[node_name])} end)
  defp part(_, _fields), do: nil

  defp field(value) when is_binary(value), do: value
  defp field(value) when is_integer(value), do: Integer.to_string(value)
  defp field(_), do: nil

  defp read_parts(transaction_hash, metadata_hash) do
    request =
      EthereumJSONRPC.request(%{id: 0, method: "eth_getTransactionByHash", params: [to_string(transaction_hash)]})

    expected = to_string(metadata_hash)

    case EthereumJSONRPC.json_rpc(request, Application.get_env(:explorer, :json_rpc_named_arguments)) do
      {:ok, %{"shnMetadataHash" => hash} = transaction_json} when is_binary(hash) ->
        if String.downcase(hash) == expected do
          parts(transaction_json)
        else
          Logger.warning(
            "Shinerium metadata: the node gives #{transaction_hash} the metadata hash #{hash}, not #{expected}"
          )

          nil
        end

      {:ok, _} ->
        nil

      {:error, reason} ->
        Logger.warning("Shinerium metadata: eth_getTransactionByHash of #{transaction_hash} failed: #{inspect(reason)}")
        nil
    end
  end
end
