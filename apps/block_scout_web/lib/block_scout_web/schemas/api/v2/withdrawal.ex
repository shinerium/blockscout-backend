# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule BlockScoutWeb.Schemas.API.V2.Withdrawal do
  @moduledoc """
  This module defines the schema for the Withdrawal struct.
  """
  require OpenApiSpex
  use Utils.CompileTimeEnvHelper, chain_type: [:explorer, :chain_type]
  alias BlockScoutWeb.Schemas.API.V2.{Address, General}
  alias OpenApiSpex.Schema

  @base_properties %{
    index: %Schema{type: :integer, nullable: false},
    validator_index: %Schema{type: :integer, nullable: false},
    amount: General.IntegerString,
    block_number: %Schema{type: :integer, nullable: false},
    receiver: Address,
    timestamp: General.Timestamp
  }

  case @chain_type do
    :shinerium ->
      @properties Map.put(@base_properties, :shinerium, %Schema{
                    type: :object,
                    nullable: false,
                    description: "The reward's type, and a committee member's identity address.",
                    properties: %{
                      reward_type: %Schema{
                        type: :string,
                        nullable: true,
                        description: "\"committee\", \"poq\", \"ecosystem\" or \"support\"."
                      },
                      validator_hash: General.AddressHashNullable
                    },
                    required: [:reward_type, :validator_hash],
                    additionalProperties: false
                  })

      @required [:index, :validator_index, :amount, :shinerium]

    _ ->
      @properties @base_properties
      @required [:index, :validator_index, :amount]
  end

  OpenApiSpex.schema(%{
    title: "BeaconWithdrawal",
    type: :object,
    properties: @properties,
    required: @required,
    additionalProperties: false
  })
end
