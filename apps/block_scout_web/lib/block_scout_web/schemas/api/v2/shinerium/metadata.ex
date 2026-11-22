# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule BlockScoutWeb.Schemas.API.V2.Shinerium.Metadata do
  @moduledoc """
  This module defines the schema of the metadata that a Shinerium metadata hash
  commits to, with the transactions that carry it.
  """
  require OpenApiSpex

  alias BlockScoutWeb.Schemas.API.V2.General
  alias Explorer.Chain.Shinerium.Metadata
  alias OpenApiSpex.Schema

  @descriptions %{
    metadata: "Off-chain references: an IPFS identifier, a URL, a note and the like; null when absent.",
    identity: "Digital identity: a DID, a verifiable credential, a biometric hash, a proof document; null when absent.",
    security: "Security attributes: a hash proof, a public key proof, keys and an attestation; null when absent.",
    iso20022: "An ISO 20022 reference: the payment type, the message type, ID and reference; null when absent."
  }

  @parts Map.new(Metadata.fields(), fn {part, fields} ->
           {part,
            %Schema{
              type: :object,
              nullable: true,
              description: @descriptions[part],
              properties: Map.new(fields, &{&1, %Schema{type: :string, nullable: true}}),
              required: fields,
              additionalProperties: false
            }}
         end)

  @first_transaction %Schema{
    type: :object,
    nullable: false,
    description: "The first transaction that carries the hash.",
    properties: %{
      hash: General.FullHash,
      block_number: %Schema{type: :integer, minimum: 0, nullable: true},
      timestamp: General.TimestampNullable
    },
    required: [:hash, :block_number, :timestamp],
    additionalProperties: false
  }

  OpenApiSpex.schema(%{
    title: "ShineriumMetadata",
    description: """
    The metadata that a Shinerium metadata hash (shnMetadataHash) commits to: its four parts, read from the node
    in the first transaction that carries the hash, with the number of transactions that carry it.
    """,
    type: :object,
    properties:
      Map.merge(@parts, %{
        metadata_hash: General.FullHash,
        transactions_count: %Schema{type: :integer, minimum: 1, nullable: false},
        first_transaction: @first_transaction,
        read_from_node: %Schema{
          type: :boolean,
          nullable: false,
          description: "Whether the node gave the fields; when false, every part is null."
        }
      }),
    required: [:metadata_hash, :transactions_count, :first_transaction, :read_from_node | Map.keys(@parts)],
    additionalProperties: false
  })
end
