# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule BlockScoutWeb.Schemas.API.V2.Shinerium.Epoch.Common do
  @moduledoc false
  alias BlockScoutWeb.Schemas.API.V2.General
  alias OpenApiSpex.Schema

  @doc "Where the beacons placed a member, or what the genesis declares: the node's location object."
  def location do
    %Schema{
      type: :object,
      nullable: true,
      additionalProperties: true,
      description:
        "Where the beacons placed the member when it joined, or what the genesis declares (`source` \"declared\"): " <>
          "country, region and autonomous system, never the address."
    }
  end

  @doc "A member's figures from the records besides its signatures (block-explorer-plan 11.18)."
  def record_properties do
    %{
      correlated: %Schema{
        type: :integer,
        nullable: true,
        description:
          "Its correlated misses: each certificate it did not sign counts as many times as members of its " <>
            "autonomous system did not sign it, itself included, at most f + 1. Null while the epoch runs, " <>
            "on a network without the correlation penalty, or from a record read without them."
      },
      credited: %Schema{
        type: :integer,
        nullable: true,
        description:
          "What the carrier that ends the epoch credits it with, its share of the reward scaled by it: " <>
            "the certificates less its correlated misses under the correlation penalty, its signatures " <>
            "without it. Null while the epoch runs, or from a record read without `correlated`."
      },
      slow: %Schema{
        type: :integer,
        nullable: true,
        description:
          "The consecutive epochs before this one that found it slow, from the record of the control " <>
            "block that seats the committee; at two it leads no views. Null for the genesis's committee " <>
            "or from a record read without it."
      }
    }
  end

  def removal do
    %Schema{
      type: :object,
      nullable: true,
      description: "Why the member left the committee at the epoch's end; null if it stays.",
      properties: %{
        code: %Schema{type: :integer, nullable: false, description: "The node's Eviction constant."},
        name: %Schema{type: :string, nullable: true}
      },
      required: [:code, :name],
      additionalProperties: false
    }
  end

  def epoch_properties do
    %{
      number: %Schema{type: :integer, minimum: 0, nullable: false, description: "The number of its control block."},
      control_block_hash: General.FullHash,
      committee_hash: General.FullHashNullable,
      started_at: General.Timestamp,
      ended_at: General.TimestampNullable,
      carrier_block_number: %Schema{
        type: :integer,
        nullable: true,
        description: "The block that carries its control block; null for the genesis's."
      },
      first_block_number: %Schema{type: :integer, nullable: false},
      end_block_number: %Schema{
        type: :integer,
        nullable: true,
        description: "Its last block, the carrier of the next control block; null while it runs."
      },
      members_count: %Schema{type: :integer, nullable: false},
      qcs: %Schema{
        type: :integer,
        nullable: true,
        description: "The quorum certificates its blocks carry; null while it runs."
      },
      signed: %Schema{
        type: :integer,
        nullable: true,
        description: "The signatures its members gave those certificates; null while it runs."
      },
      absent_kept: %Schema{type: :integer, nullable: true},
      joined_count: %Schema{type: :integer, nullable: true},
      joined_seal: joined_seal(),
      removed_count: %Schema{type: :integer, nullable: true},
      is_current: %Schema{type: :boolean, nullable: false}
    }
  end

  @doc "What the seal nonce of the control block that ends an epoch says of the candidate it seats."
  def joined_seal do
    %Schema{
      type: :object,
      nullable: true,
      description:
        "The seal of the candidate that the control block ending the epoch seats: its nonce names the PoRC " <>
          "generation (the base generation, 2, writes none), the proof's version and the tier. Null when it " <>
          "seats none, while the epoch runs, or for an epoch stored before the explorer read it.",
      properties: %{
        nonce: %Schema{type: :string, pattern: ~r/^0x[0-9a-f]{16}$/, nullable: false},
        porc_generation: %Schema{type: :integer, minimum: 0, nullable: false},
        porc_version: %Schema{type: :integer, minimum: 0, nullable: false},
        tier: %Schema{type: :string, nullable: true, description: "validator, support or basic"}
      },
      required: [:nonce, :porc_generation, :porc_version, :tier],
      additionalProperties: false
    }
  end
end

defmodule BlockScoutWeb.Schemas.API.V2.Shinerium.Epoch.Progress do
  @moduledoc """
  The Shinerium epoch that runs now and how far it has come.
  """
  require OpenApiSpex

  alias BlockScoutWeb.Schemas.API.V2.General
  alias OpenApiSpex.Schema

  @properties %{
    number: %Schema{type: :integer, minimum: 0, nullable: false, description: "The number of its control block."},
    started_at: General.Timestamp,
    ended_at: General.TimestampNullable,
    carrier_block_number: %Schema{
      type: :integer,
      nullable: true,
      description: "Its base: the block that carries its control block; null for the genesis's."
    },
    latest_block: %Schema{
      type: :object,
      nullable: false,
      properties: %{
        number: %Schema{type: :integer, minimum: 0, nullable: false},
        timestamp: General.Timestamp
      },
      required: [:number, :timestamp],
      additionalProperties: false
    },
    blocks: %Schema{type: :integer, minimum: 0, nullable: false, description: "Blocks since its base."},
    max_blocks: %Schema{
      type: :integer,
      minimum: 1,
      nullable: false,
      description: "The most blocks an epoch has (the genesis's maxEpochBlocks)."
    },
    seconds: %Schema{
      type: :integer,
      minimum: 0,
      nullable: false,
      description: "Seconds since its base, by the latest block's timestamp."
    },
    max_seconds: %Schema{
      type: :integer,
      minimum: 1,
      nullable: false,
      description: "The longest an epoch lasts (the genesis's maxEpochSeconds)."
    },
    progress: %Schema{
      type: :number,
      minimum: 0,
      maximum: 1,
      nullable: false,
      description: "How far it has come: the larger of blocks / max_blocks and seconds / max_seconds, at most 1."
    }
  }

  OpenApiSpex.schema(%{
    title: "ShineriumEpochProgress",
    description: """
    The epoch that runs now. It ends after at most `max_blocks` blocks and at most `max_seconds`, whichever
    comes first (the node's specification, 10.1).
    """,
    type: :object,
    properties: @properties,
    required: Map.keys(@properties),
    additionalProperties: false
  })
end

defmodule BlockScoutWeb.Schemas.API.V2.Shinerium.Epoch do
  @moduledoc """
  An epoch of the Shinerium chain in the list of epochs.
  """
  require OpenApiSpex

  alias BlockScoutWeb.Schemas.API.V2.Shinerium.Epoch.Common

  OpenApiSpex.schema(%{
    title: "ShineriumEpoch",
    type: :object,
    properties: Common.epoch_properties(),
    required: Map.keys(Common.epoch_properties()),
    additionalProperties: false
  })
end

defmodule BlockScoutWeb.Schemas.API.V2.Shinerium.Epoch.Detailed do
  @moduledoc """
  An epoch of the Shinerium chain with its committee and the nodes that join at
  its end.
  """
  require OpenApiSpex

  alias BlockScoutWeb.Schemas.API.V2.General
  alias BlockScoutWeb.Schemas.API.V2.Shinerium.Epoch.Common
  alias OpenApiSpex.Schema

  @member_properties Map.merge(Common.record_properties(), %{
                       index: %Schema{type: :integer, nullable: false},
                       identity: General.FullHash,
                       ed_address_hash: General.AddressHash,
                       name: %Schema{type: :string, nullable: true},
                       coinbase_hash: General.AddressHashNullable,
                       pq_key_hash: General.FullHashNullable,
                       location: Common.location(),
                       signed: %Schema{type: :integer, nullable: true},
                       removal: Common.removal(),
                       reward: General.IntegerStringNullable
                     })

  @member %Schema{
    type: :object,
    properties: @member_properties,
    required: Map.keys(@member_properties),
    additionalProperties: false
  }

  @joined %Schema{
    type: :object,
    properties: %{
      identity: General.FullHashNullable,
      ed_address_hash: General.AddressHashNullable,
      coinbase_hash: General.AddressHashNullable,
      pq_key_hash: General.FullHashNullable,
      location: Common.location()
    },
    required: [:identity, :ed_address_hash, :coinbase_hash, :pq_key_hash, :location],
    additionalProperties: false
  }

  @properties Map.merge(Common.epoch_properties(), %{
                next_first: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "The committee index of the member the next committee starts with."
                },
                members: %Schema{type: :array, items: @member, nullable: false},
                joined: %Schema{type: :array, items: @joined, nullable: true}
              })

  OpenApiSpex.schema(%{
    title: "ShineriumEpochDetailed",
    type: :object,
    properties: @properties,
    required: Map.keys(@properties),
    additionalProperties: false
  })
end
