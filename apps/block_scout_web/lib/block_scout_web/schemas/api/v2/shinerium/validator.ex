# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule BlockScoutWeb.Schemas.API.V2.Shinerium.Validator.Common do
  @moduledoc false
  alias BlockScoutWeb.Schemas.API.V2.General
  alias BlockScoutWeb.Schemas.API.V2.Shinerium.Epoch
  alias OpenApiSpex.Schema

  def properties do
    %{
      identity: General.FullHash,
      ed_address_hash: General.AddressHash,
      name: %Schema{type: :string, nullable: true},
      status: %Schema{
        type: :string,
        nullable: true,
        description:
          "The bond's status: none, pending, active, exiting, releasing, releasable or released; " <>
            "null until the node has been asked (shn_getValidator)."
      },
      genesis: %Schema{type: :boolean, nullable: true, description: "Whether the genesis made the bond."},
      amount: General.IntegerStringNullable,
      is_member: %Schema{type: :boolean, nullable: false, description: "Whether it sits in the epoch that runs."},
      epochs: %Schema{type: :integer, nullable: false, description: "The epochs it served."},
      first_epoch: %Schema{type: :integer, nullable: true},
      last_epoch: %Schema{type: :integer, nullable: true},
      signed: %Schema{
        type: :integer,
        nullable: true,
        description: "The certificates it signed in the epochs it served that have ended."
      },
      qcs: %Schema{type: :integer, nullable: true, description: "The certificates of those epochs."},
      rewards_total: General.IntegerStringNullable,
      rewards_count: %Schema{type: :integer, nullable: false},
      location: %Schema{
        Epoch.Common.location()
        | description:
            "Its location in the latest epoch that gives one, as the committee has it: where the beacons " <>
              "placed it when it joined, or what the genesis declares (`source` \"declared\"); null if none does."
      },
      location_epoch: %Schema{
        type: :integer,
        nullable: true,
        description: "The epoch whose committee gives `location`."
      }
    }
  end
end

defmodule BlockScoutWeb.Schemas.API.V2.Shinerium.Validator do
  @moduledoc """
  A Shinerium validator in the list of validators.
  """
  require OpenApiSpex

  alias BlockScoutWeb.Schemas.API.V2.Shinerium.Validator.Common

  OpenApiSpex.schema(%{
    title: "ShineriumValidator",
    type: :object,
    properties: Common.properties(),
    required: Map.keys(Common.properties()),
    additionalProperties: false
  })
end

defmodule BlockScoutWeb.Schemas.API.V2.Shinerium.Validator.Detailed do
  @moduledoc """
  A Shinerium validator with its bond and penalty box, as the node's
  `shn_getValidator` gives them.
  """
  require OpenApiSpex

  alias BlockScoutWeb.Schemas.API.V2.General
  alias BlockScoutWeb.Schemas.API.V2.Shinerium.Validator.Common
  alias OpenApiSpex.Schema

  @penalty %Schema{
    type: :object,
    nullable: true,
    description: "A forced exit's penalty; null without one.",
    properties: %{
      reason: %Schema{type: :string, nullable: true},
      active: %Schema{type: :boolean, nullable: true},
      awaiting_removal: %Schema{type: :boolean, nullable: true},
      until: General.TimestampNullable,
      requires_rebond: %Schema{type: :boolean, nullable: true}
    },
    required: [:reason, :active, :awaiting_removal, :until, :requires_rebond],
    additionalProperties: false
  }

  @penalty_box %Schema{
    type: :object,
    nullable: true,
    description: "The penalty box, in the epoch of the block the bond was read at.",
    properties: %{
      seat_from: %Schema{type: :integer, nullable: true},
      since: %Schema{type: :integer, nullable: true},
      strikes: %Schema{type: :integer, nullable: true},
      reason: %Schema{type: :integer, nullable: true},
      reason_name: %Schema{type: :string, nullable: true},
      active: %Schema{type: :boolean, nullable: true},
      epochs_left: %Schema{type: :integer, nullable: true}
    },
    required: [:seat_from, :since, :strikes, :reason, :reason_name, :active, :epochs_left],
    additionalProperties: false
  }

  @properties Map.merge(Common.properties(), %{
                bond_owner_hash: General.AddressHashNullable,
                refund_address_hash: General.AddressHashNullable,
                bls_hash: General.FullHashNullable,
                pq_hash: General.FullHashNullable,
                active_at: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "The block from which the bond is active."
                },
                exiting: %Schema{type: :boolean, nullable: true},
                release_at: General.TimestampNullable,
                forced_exit: %Schema{type: :boolean, nullable: true},
                required: General.IntegerStringNullable,
                shortfall: General.IntegerStringNullable,
                penalty: @penalty,
                penalty_box: @penalty_box,
                bond_block_number: %Schema{
                  type: :integer,
                  nullable: true,
                  description: "The block the bond was read at."
                }
              })

  OpenApiSpex.schema(%{
    title: "ShineriumValidatorDetailed",
    type: :object,
    properties: @properties,
    required: Map.keys(@properties),
    additionalProperties: false
  })
end

defmodule BlockScoutWeb.Schemas.API.V2.Shinerium.Validator.Epoch do
  @moduledoc """
  An epoch a Shinerium validator served.
  """
  require OpenApiSpex

  alias BlockScoutWeb.Schemas.API.V2.General
  alias BlockScoutWeb.Schemas.API.V2.Shinerium.Epoch.Common
  alias OpenApiSpex.Schema

  @properties Map.merge(Common.record_properties(), %{
                epoch_number: %Schema{type: :integer, nullable: false},
                index: %Schema{type: :integer, nullable: false, description: "Its seat in the epoch's committee."},
                started_at: General.Timestamp,
                ended_at: General.TimestampNullable,
                signed: %Schema{type: :integer, nullable: true},
                qcs: %Schema{type: :integer, nullable: true},
                removal: Common.removal(),
                reward: General.IntegerStringNullable
              })

  OpenApiSpex.schema(%{
    title: "ShineriumValidatorEpoch",
    type: :object,
    properties: @properties,
    required: Map.keys(@properties),
    additionalProperties: false
  })
end

defmodule BlockScoutWeb.Schemas.API.V2.Shinerium.BlockConsensus do
  @moduledoc """
  A Shinerium block's consensus: its epoch and view, the certificate of its
  parent that it carries, and its own certificate, which its child carries.
  """
  require OpenApiSpex

  alias BlockScoutWeb.Schemas.API.V2.General
  alias OpenApiSpex.Schema

  @signer %Schema{
    type: :object,
    properties: %{
      index: %Schema{type: :integer, nullable: false},
      identity: General.FullHashNullable,
      ed_address_hash: General.AddressHashNullable,
      name: %Schema{type: :string, nullable: true}
    },
    required: [:index, :identity, :ed_address_hash, :name],
    additionalProperties: false
  }

  @certificate %Schema{
    type: :object,
    nullable: true,
    properties: %{
      certified_block_number: %Schema{type: :integer, nullable: false},
      certified_block_hash: General.FullHash,
      carried_by_block_number: %Schema{type: :integer, nullable: false},
      carried_by_block_hash: General.FullHash,
      epoch: %Schema{type: :integer, nullable: true},
      view: %Schema{type: :integer, nullable: true},
      scheme: %Schema{
        type: :object,
        nullable: false,
        properties: %{
          id: %Schema{type: :integer, nullable: true},
          name: %Schema{type: :string, nullable: true}
        },
        required: [:id, :name],
        additionalProperties: false
      },
      committee_size: %Schema{
        type: :integer,
        nullable: true,
        description: "The size of the committee that signs it; null when the explorer has not read it."
      },
      signers: %Schema{type: :array, items: @signer, nullable: false}
    },
    required: [
      :certified_block_number,
      :certified_block_hash,
      :carried_by_block_number,
      :carried_by_block_hash,
      :epoch,
      :view,
      :scheme,
      :committee_size,
      :signers
    ],
    additionalProperties: false
  }

  OpenApiSpex.schema(%{
    title: "ShineriumBlockConsensus",
    type: :object,
    properties: %{
      epoch: %Schema{type: :integer, nullable: true},
      view: %Schema{type: :integer, nullable: true},
      justify: %Schema{@certificate | description: "The parent's certificate, which the block carries."},
      certificate: %Schema{@certificate | description: "The block's own certificate, which its child carries."}
    },
    required: [:epoch, :view, :justify, :certificate],
    additionalProperties: false
  })
end
