# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule BlockScoutWeb.Schemas.API.V2.Shinerium.Account do
  @moduledoc """
  This module defines the schema of a Shinerium account's post-quantum key and
  vesting, as the node gives them at the latest block.
  """
  require OpenApiSpex

  alias BlockScoutWeb.Schemas.API.V2.General
  alias BlockScoutWeb.Schemas.Helper
  alias OpenApiSpex.Schema

  @scheme %Schema{
    type: :object,
    nullable: true,
    properties: %{
      id: %Schema{type: :integer, nullable: false},
      name: %Schema{type: :string, nullable: false}
    },
    required: [:id, :name],
    additionalProperties: false
  }

  @account_key %Schema{
    type: :object,
    nullable: true,
    description: "The account's post-quantum key (shn_getAccountKey); null when the node gives none.",
    properties: %{
      policy: %Schema{
        type: :string,
        nullable: false,
        description: "\"none\", \"optional\", \"required\" or \"pq-only\"."
      },
      scheme: %Schema{@scheme | description: "The key's scheme; null without a key."},
      version: %Schema{type: :integer, minimum: 0, nullable: false},
      changed_at_block: %Schema{type: :integer, minimum: 0, nullable: false},
      key_hash: General.FullHashNullable,
      verifiable: %Schema{
        type: :boolean,
        nullable: false,
        description: "Whether a witness by the key verifies in the next block."
      }
    },
    required: [:policy, :scheme, :version, :changed_at_block, :key_hash, :verifiable],
    additionalProperties: false
  }

  @record %Schema{
    type: :object,
    nullable: true,
    description: "The account's vesting record; null without one.",
    properties: %{
      amount: General.IntegerString,
      start: General.TimestampNullable,
      cliff: General.TimestampNullable,
      end: General.TimestampNullable,
      step: %Schema{
        type: :integer,
        minimum: 0,
        nullable: false,
        description: "Seconds between vestings; 0 vests continuously."
      },
      pool: %Schema{type: :boolean, nullable: false, description: "Whether the record is a grant pool."}
    },
    required: [:amount, :start, :cliff, :end, :step, :pool],
    additionalProperties: false
  }

  @vesting %Schema{
    type: :object,
    nullable: true,
    description: "What the account may spend now (shn_getVesting); null when the node gives none.",
    properties: %{
      locked_until:
        Helper.describe_inline(General.TimestampNullable.schema(), "The time lock's end; null without a lock."),
      wholly_locked: %Schema{
        type: :boolean,
        nullable: false,
        description: "A lock without a vesting record: the account can send no transaction."
      },
      locked: General.IntegerStringNullable,
      spendable: General.IntegerStringNullable,
      vested: General.IntegerStringNullable,
      next_vest: General.TimestampNullable,
      record: @record
    },
    required: [:locked_until, :wholly_locked, :locked, :spendable, :vested, :next_vest, :record],
    additionalProperties: false
  }

  OpenApiSpex.schema(%{
    title: "ShineriumAccount",
    description: "A Shinerium account's post-quantum key and vesting, read from the node at the latest block.",
    type: :object,
    properties: %{
      account_key: @account_key,
      vesting: @vesting
    },
    required: [:account_key, :vesting],
    additionalProperties: false
  })
end
