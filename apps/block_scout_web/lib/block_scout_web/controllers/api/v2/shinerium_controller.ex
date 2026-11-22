# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule BlockScoutWeb.API.V2.ShineriumController do
  use BlockScoutWeb, :controller
  use OpenApiSpex.ControllerSpecs

  import BlockScoutWeb.Chain, only: [parse_block_hash_or_number_param: 1, paginate_list: 3, paginate_list: 4]

  import Explorer.Chain.Address.MetadataPreloader, only: [maybe_preload_ens_and_metadata: 2]

  alias BlockScoutWeb.AccessHelper
  alias BlockScoutWeb.API.V2.{ShineriumView, TransactionView}
  alias BlockScoutWeb.Schemas.API.V2.ErrorResponses.NotFoundResponse
  alias Explorer.{Chain, PagingOptions}
  alias Explorer.Chain.Shinerium.{Account, Consensus, Metadata}
  alias OpenApiSpex.{Parameter, Schema}

  @page_size 50
  @api_true [api?: true]

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

  @metadata_hash_param %Parameter{
    name: :metadata_hash_param,
    in: :path,
    schema: Schemas.General.FullHash,
    required: true,
    description: "The metadata hash (shnMetadataHash) that extended transactions carry"
  }

  operation :metadata,
    summary: "Get the metadata that a Shinerium metadata hash commits to.",
    description: """
    The hash is the Keccak-256 of an extended transaction's metadata fields, and the node refuses a transaction
    whose hash does not commit to its fields, so every transaction that carries the hash carries the same fields.
    They are read from the node (`eth_getTransactionByHash`) in the first transaction that carries the hash; only
    the hash is indexed.
    """,
    parameters: [@metadata_hash_param | base_params()],
    responses: [
      ok: {"The metadata.", "application/json", Schemas.Shinerium.Metadata},
      unprocessable_entity: JsonErrorResponse.response(),
      not_found: NotFoundResponse.response()
    ]

  @doc """
  Handles GET requests to `/api/v2/shinerium/metadata/:metadata_hash_param`.
  """
  @spec metadata(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:format, :error} | {:error, :not_found}
  def metadata(conn, %{metadata_hash_param: hash_string}) do
    with {:format, {:ok, metadata_hash}} <- {:format, Chain.string_to_full_hash(hash_string)},
         {:ok, metadata} <- Metadata.fetch(metadata_hash, @api_true) do
      json(conn, ShineriumView.metadata_json(metadata))
    end
  end

  operation :metadata_transactions,
    summary: "List the transactions that carry a Shinerium metadata hash, the newest first.",
    parameters: [@metadata_hash_param | base_params()] ++ define_paging_params(["block_number", "index"]),
    responses: [
      ok:
        {"Transactions.", "application/json",
         paginated_response(
           items: Schemas.Transaction,
           next_page_params_example: %{"block_number" => 144_359, "index" => 0}
         )},
      unprocessable_entity: JsonErrorResponse.response()
    ]

  @doc """
  Handles GET requests to `/api/v2/shinerium/metadata/:metadata_hash_param/transactions`.
  """
  @spec metadata_transactions(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:format, :error}
  def metadata_transactions(conn, %{metadata_hash_param: hash_string} = params) do
    with {:format, {:ok, metadata_hash}} <- {:format, Chain.string_to_full_hash(hash_string)} do
      full_options =
        transaction_necessity_by_association()
        |> Keyword.merge(BlockScoutWeb.Chain.paging_options(params))
        |> Keyword.merge(@api_true)

      transactions_plus_one = Metadata.transactions(metadata_hash, full_options)
      {transactions, next_page_params} = paginate_list(transactions_plus_one, params, full_options[:paging_options])

      conn
      |> put_status(200)
      |> put_view(TransactionView)
      |> render(:transactions, %{
        transactions: maybe_preload_ens_and_metadata(transactions, :transactions),
        next_page_params: next_page_params
      })
    end
  end

  # As a block's transactions (BlockController); the chain type adds no association.
  defp transaction_necessity_by_association do
    address = [:scam_badge, :names, proxy_implementations_association()]

    [
      necessity_by_association: %{
        [created_contract_address: address] => :optional,
        [from_address: address] => :optional,
        [to_address: address] => :optional,
        :block => :optional
      }
    ]
  end

  @epoch_number_param %Parameter{
    name: :number,
    in: :path,
    schema: %Schema{type: :integer, minimum: 0},
    required: true,
    description: "The epoch's number, that of the control block that starts it"
  }

  @validator_id_param %Parameter{
    name: :id,
    in: :path,
    schema: %Schema{type: :string, pattern: ~r/^0x([0-9a-fA-F]{40}|[0-9a-fA-F]{64})$/},
    required: true,
    description: "The validator's Ed25519 identity key (32 bytes) or its identity address (20 bytes)"
  }

  @number_paging_param %Parameter{
    name: :number,
    in: :query,
    schema: %Schema{type: :integer, minimum: 0},
    required: false,
    description: "The epoch number to continue below"
  }

  operation :epochs,
    summary: "List the Shinerium chain's epochs, the newest first.",
    parameters: [@number_paging_param | base_params()],
    responses: [
      ok:
        {"Epochs.", "application/json",
         paginated_response(items: Schemas.Shinerium.Epoch, next_page_params_example: %{"number" => 238})},
      unprocessable_entity: JsonErrorResponse.response()
    ]

  @doc """
  Handles GET requests to `/api/v2/shinerium/epochs`.
  """
  @spec epochs(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def epochs(conn, params) do
    paging_options = paging_options(params)
    current = Consensus.current_epoch_number()

    {epochs, next_page_params} =
      paging_options
      |> Consensus.epochs()
      |> paginate_list(%{}, paging_options, paging_function: &%{number: &1.epoch.number})

    json(conn, %{
      items: Enum.map(epochs, &ShineriumView.epoch_json(&1, current)),
      next_page_params: next_page_params
    })
  end

  operation :epoch_progress,
    summary: "Get the Shinerium epoch that runs now and how far it has come.",
    description: """
    The epoch with the highest stored number, the blocks and seconds since its base at the latest block, and its
    progress: the larger share of the epoch's two bounds (block-explorer-plan 11.30).
    """,
    parameters: base_params(),
    responses: [
      ok: {"The epoch that runs now.", "application/json", Schemas.Shinerium.Epoch.Progress},
      not_found: NotFoundResponse.response()
    ]

  @doc """
  Handles GET requests to `/api/v2/shinerium/epochs/current`.
  """
  @spec epoch_progress(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, :not_found}
  def epoch_progress(conn, _params) do
    case Consensus.epoch_progress() do
      nil -> {:error, :not_found}
      progress -> json(conn, ShineriumView.epoch_progress_json(progress))
    end
  end

  operation :epoch,
    summary: "Get a Shinerium epoch with its committee.",
    parameters: [@epoch_number_param | base_params()],
    responses: [
      ok: {"The epoch.", "application/json", Schemas.Shinerium.Epoch.Detailed},
      unprocessable_entity: JsonErrorResponse.response(),
      not_found: NotFoundResponse.response()
    ]

  @doc """
  Handles GET requests to `/api/v2/shinerium/epochs/:number`.
  """
  @spec epoch(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, :not_found}
  def epoch(conn, %{number: number}) do
    with {:ok, epoch} <- Consensus.epoch(number) do
      json(conn, ShineriumView.epoch_detail_json(epoch, Consensus.current_epoch_number()))
    end
  end

  operation :validators,
    summary: "List the Shinerium validators, the committee's members first.",
    parameters: base_params(),
    responses: [
      ok:
        {"Validators.", "application/json",
         paginated_response(items: Schemas.Shinerium.Validator, next_page_params_example: nil)},
      unprocessable_entity: JsonErrorResponse.response()
    ]

  @doc """
  Handles GET requests to `/api/v2/shinerium/validators`.
  """
  @spec validators(Plug.Conn.t(), map()) :: Plug.Conn.t()
  def validators(conn, _params) do
    json(conn, %{items: Enum.map(Consensus.validators(), &ShineriumView.validator_json/1), next_page_params: nil})
  end

  operation :validator,
    summary: "Get a Shinerium validator with its bond.",
    parameters: [@validator_id_param | base_params()],
    responses: [
      ok: {"The validator.", "application/json", Schemas.Shinerium.Validator.Detailed},
      unprocessable_entity: JsonErrorResponse.response(),
      not_found: NotFoundResponse.response()
    ]

  @doc """
  Handles GET requests to `/api/v2/shinerium/validators/:id`.
  """
  @spec validator(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, :not_found}
  def validator(conn, %{id: id}) do
    with {:ok, row} <- id |> id_bytes() |> Consensus.validator() do
      json(conn, ShineriumView.validator_detail_json(row))
    end
  end

  operation :validator_epochs,
    summary: "List the epochs a Shinerium validator served, the newest first.",
    parameters: [@validator_id_param, @number_paging_param | base_params()],
    responses: [
      ok:
        {"Epochs.", "application/json",
         paginated_response(items: Schemas.Shinerium.Validator.Epoch, next_page_params_example: %{"number" => 238})},
      unprocessable_entity: JsonErrorResponse.response(),
      not_found: NotFoundResponse.response()
    ]

  @doc """
  Handles GET requests to `/api/v2/shinerium/validators/:id/epochs`.
  """
  @spec validator_epochs(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, :not_found}
  def validator_epochs(conn, %{id: id} = params) do
    with {:ok, %{validator: validator}} <- id |> id_bytes() |> Consensus.validator() do
      paging_options = paging_options(params)

      {epochs, next_page_params} =
        validator.identity
        |> Consensus.validator_epochs(validator.ed_address_hash, paging_options)
        |> paginate_list(%{}, paging_options, paging_function: &%{number: &1.member.epoch_number})

      json(conn, %{items: Enum.map(epochs, &ShineriumView.validator_epoch_json/1), next_page_params: next_page_params})
    end
  end

  operation :block_consensus,
    summary: "Get a Shinerium block's consensus: its epoch, view and quorum certificates.",
    parameters: [block_hash_or_number_param() | base_params()],
    responses: [
      ok: {"The block's consensus.", "application/json", Schemas.Shinerium.BlockConsensus},
      unprocessable_entity: JsonErrorResponse.response(),
      not_found: NotFoundResponse.response()
    ]

  @doc """
  Handles GET requests to `/api/v2/shinerium/blocks/:block_hash_or_number_param/consensus`.
  """
  @spec block_consensus(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, any()}
  def block_consensus(conn, %{block_hash_or_number_param: param}) do
    with {:ok, type, value} <- parse_block_hash_or_number_param(param),
         {:ok, block} <- fetch_block(type, value) do
      json(conn, ShineriumView.block_consensus_json(Consensus.block_consensus(block)))
    end
  end

  defp fetch_block(:hash, hash), do: Chain.hash_to_block(hash, api?: true)
  defp fetch_block(:number, number), do: Chain.number_to_block(number, api?: true)

  defp paging_options(params) do
    key = if is_integer(params[:number]), do: %{number: params[:number]}
    %PagingOptions{key: key, page_size: @page_size + 1}
  end

  defp id_bytes("0x" <> hex) do
    case Base.decode16(hex, case: :mixed) do
      {:ok, bytes} -> bytes
      :error -> nil
    end
  end

  defp id_bytes(_), do: nil
end
