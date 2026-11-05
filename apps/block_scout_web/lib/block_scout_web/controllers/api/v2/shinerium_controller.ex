# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule BlockScoutWeb.API.V2.ShineriumController do
  use BlockScoutWeb, :controller
  use OpenApiSpex.ControllerSpecs

  alias BlockScoutWeb.AccessHelper
  alias BlockScoutWeb.API.V2.ShineriumView
  alias Explorer.Chain
  alias Explorer.Chain.Shinerium.Account

  plug(OpenApiSpex.Plug.CastAndValidate, json_render_error_v2: true)

  tags(["shinerium"])

  action_fallback(BlockScoutWeb.API.V2.FallbackController)

  operation :address,
    summary: "Get a Shinerium account's post-quantum key and vesting.",
    description: """
    Reads the account's post-quantum key (`shn_getAccountKey`) and vesting (`shn_getVesting`) from the node at
    the latest block. Neither is indexed: both change with the account's operations, and vesting with time.
    """,
    parameters: [address_hash_param() | base_params()],
    responses: [
      ok: {"The account's post-quantum key and vesting.", "application/json", Schemas.Shinerium.Account},
      unprocessable_entity: JsonErrorResponse.response(),
      forbidden: ForbiddenResponse.response()
    ]

  @doc """
  Handles GET requests to `/api/v2/shinerium/addresses/:address_hash_param`.
  """
  @spec address(Plug.Conn.t(), map()) :: {:format, :error} | {:restricted_access, true} | Plug.Conn.t()
  def address(conn, %{address_hash_param: address_hash_string} = params) do
    with {:format, {:ok, address_hash}} <- {:format, Chain.string_to_address_hash(address_hash_string)},
         {:ok, false} <- AccessHelper.restricted_access?(address_hash_string, params) do
      json(conn, ShineriumView.account_json(Account.fetch(address_hash)))
    end
  end
end
