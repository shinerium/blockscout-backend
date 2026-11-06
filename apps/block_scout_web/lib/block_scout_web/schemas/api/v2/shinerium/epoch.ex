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
      removed_count: %Schema{type: :integer, nullable: true},
      is_current: %Schema{type: :boolean, nullable: false}
    }
  end
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

  @member %Schema{
    type: :object,
    properties: %{
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
    },
    required: [
      :index,
      :identity,
      :ed_address_hash,
      :name,
      :coinbase_hash,
      :pq_key_hash,
      :location,
      :signed,
      :removal,
      :reward
    ],
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
