# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Indexer.Fetcher.Shinerium.Epochs do
  @moduledoc """
  Fetches the Shinerium chain's epochs, committees and validators from the node
  (block-explorer-plan 6.1, stage B), once a minute.

  - Epochs: for every epoch not yet ended in the database, from the first such
    one to the latest control block, its control block
    (`shn_getControlBlockByNumber`), its committee (`shn_committeeMembers`) and,
    once it has ended, the next control block, whose record says how it went.
    A running epoch is stored as far as it is known, and again when it ends.
  - Validators: each identity seen in a committee, or among the nodes that join
    one, gets a row; its bond is read with `shn_getValidator` at the latest
    block, the identities read longest ago first. A node without that method
    (before R5, 0.2.0-39ebea86) leaves the bond's fields empty.
  """

  use GenServer

  require Logger

  alias Explorer.Chain.{Hash, Wei}
  alias Explorer.Chain.Shinerium.Consensus

  @interval :timer.minutes(1)
  # epochs a round asks about in one JSON-RPC batch (three calls each at most)
  @epochs_per_batch 25
  @validators_per_round 50

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(args) do
    GenServer.start_link(__MODULE__, args, name: Keyword.get(args, :name, __MODULE__))
  end

  @impl GenServer
  def init(args) do
    config = Application.get_env(:indexer, __MODULE__, [])

    state = %{
      json_rpc_named_arguments:
        Keyword.get(args, :json_rpc_named_arguments) || Application.get_env(:indexer, :json_rpc_named_arguments),
      interval: Keyword.get(args, :interval) || Keyword.get(config, :interval, @interval)
    }

    send(self(), :update)
    {:ok, state}
  end

  @impl GenServer
  def handle_info(:update, state) do
    update(state)
    Process.send_after(self(), :update, state.interval)
    {:noreply, state}
  end

  @doc """
  One round: the epochs not yet ended, then the validators' bonds.
  """
  @spec update(map()) :: :ok
  def update(%{json_rpc_named_arguments: args}) do
    with {:ok, latest} <- call(args, "shn_controlBlockNumber", []),
         {:ok, latest} <- quantity(latest) do
      sync_epochs_up_to(latest, args)
    else
      error -> Logger.warning("Shinerium epochs: the latest control block: #{inspect(error)}")
    end

    refresh_validators(args)
    :ok
  end

  # From the first epoch not ended, a batch at a time, until one fails.
  defp sync_epochs_up_to(latest, args) do
    first = (Consensus.last_ended_epoch() || -1) + 1

    if first <= latest do
      first..latest
      |> Enum.chunk_every(@epochs_per_batch)
      |> Enum.reduce_while(:ok, &continue_sync(&1, &2, latest, args))
    end
  end

  defp continue_sync(numbers, :ok, latest, args) do
    case sync_epochs(numbers, latest, args) do
      :ok -> {:cont, :ok}
      :error -> {:halt, :error}
    end
  end

  defp sync_epochs(numbers, latest, args) do
    control_numbers = Enum.uniq(numbers ++ Enum.filter([List.last(numbers) + 1], &(&1 <= latest)))

    requests =
      Enum.map(control_numbers, &request({:control, &1}, "shn_getControlBlockByNumber", [integer_to_quantity(&1)])) ++
        Enum.map(numbers, &request({:committee, &1}, "shn_committeeMembers", [integer_to_quantity(&1)]))

    with {:ok, responses} <- batch(args, requests),
         {:ok, epochs, members} <- build(numbers, responses) do
      case Consensus.import_epochs(epochs, members) do
        {:ok, _} ->
          Consensus.upsert_validators(validator_rows(epochs, members))
          :ok

        {:error, reason} ->
          Logger.error("Shinerium epochs: storing #{inspect(numbers)} failed: #{inspect(reason)}")
          :error
      end
    else
      error ->
        Logger.warning("Shinerium epochs: #{List.first(numbers)}..#{List.last(numbers)}: #{inspect(error)}")
        :error
    end
  end

  @doc """
  The rows of epochs and their members from the node's answers, keyed
  `{:control, number}` and `{:committee, number}`.
  """
  @spec build([non_neg_integer()], map()) :: {:ok, [map()], [map()]} | {:error, term()}
  def build(numbers, responses) do
    Enum.reduce_while(numbers, {:ok, [], []}, fn number, {:ok, epochs, members} ->
      control = responses[{:control, number}]
      committee = responses[{:committee, number}]

      if is_map(control) and is_list(committee) do
        {epoch, epoch_members} = epoch_rows(number, control, committee, responses[{:control, number + 1}])
        {:cont, {:ok, [epoch | epochs], epoch_members ++ members}}
      else
        {:halt, {:error, {:epoch_missing, number}}}
      end
    end)
    |> case do
      {:ok, epochs, members} -> {:ok, Enum.reverse(epochs), members}
      error -> error
    end
  end

  defp epoch_rows(number, control, committee, next) do
    epoch =
      Map.merge(
        %{
          number: number,
          control_block_hash: cast!(Hash.Full, control["hash"]),
          committee_hash: cast(Hash.Full, control["committeeHash"]),
          started_at: time(control["timestamp"]),
          carrier_block_number: carrier(number, control),
          members_count: length(committee)
        },
        epoch_end(number, next)
      )

    members =
      committee
      |> Enum.with_index()
      |> Enum.map(&member_row(&1, number, record(next)))

    {epoch, members}
  end

  # What the next control block records of the epoch it ends; nil before it exists.
  defp record(%{"epoch" => %{} = record}), do: record
  defp record(_next), do: nil

  defp epoch_end(number, next) do
    case record(next) do
      nil ->
        %{ended_at: nil, end_block_number: nil, qcs: nil, absent_kept: nil, next_first: nil, joined: nil}

      record ->
        %{
          ended_at: time(next["timestamp"]),
          end_block_number: carrier(number + 1, next),
          qcs: record["qcs"],
          absent_kept: record["absentKept"],
          next_first: record["first"],
          joined: Enum.map(record["joined"] || [], &node_summary/1)
        }
    end
  end

  defp member_row({node, index}, number, record) do
    %{
      epoch_number: number,
      index: index,
      identity: cast!(Hash.Full, prefixed(node["edPublic"])),
      ed_address_hash: cast!(Hash.Address, node["edAddress"]),
      coinbase_hash: cast(Hash.Address, node["coinbase"]),
      pq_key_hash: cast(Hash.Full, prefixed(node["pqKeyHash"])),
      location: node["location"],
      signed: record && Enum.at(record["signed"] || [], index),
      removal_reason: record && removal_reason(record, index)
    }
  end

  defp removal_reason(record, index) do
    Enum.find_value(record["removed"] || [], fn removal -> removal["index"] == index && removal["reason"] end)
  end

  defp prefixed(nil), do: nil
  defp prefixed(hex), do: "0x" <> String.replace_prefix(hex, "0x", "")

  # The block that carries a control block is the one after the transaction
  # block it names; the genesis's control block has none.
  defp carrier(0, _control), do: nil
  defp carrier(_number, %{"previousTxBlockNumber" => previous}) when is_integer(previous), do: previous + 1
  defp carrier(_number, _control), do: nil

  defp node_summary(node) do
    Map.take(node, ~w(edPublic edAddress coinbase pqKeyHash location))
  end

  defp validator_rows(epochs, members) do
    joined =
      epochs
      |> Enum.flat_map(&(&1.joined || []))
      |> Enum.flat_map(fn node ->
        with {:ok, identity} <- Hash.Full.cast(prefixed(node["edPublic"]) || ""),
             {:ok, address} <- Hash.Address.cast(node["edAddress"]) do
          [%{identity: identity, ed_address_hash: address}]
        else
          _ -> []
        end
      end)

    (Enum.map(members, &%{identity: &1.identity, ed_address_hash: &1.ed_address_hash}) ++ joined)
    |> Enum.uniq_by(& &1.identity.bytes)
  end

  @doc """
  Reads the bonds of the validators read longest ago, as many as a round takes.
  """
  @spec refresh_validators(keyword()) :: :ok
  def refresh_validators(args) do
    identities = Consensus.validator_identities(@validators_per_round)

    requests = Enum.map(identities, &request({:validator, &1}, "shn_getValidator", [to_string(&1), "latest"]))

    case identities != [] && batch(args, requests) do
      {:ok, responses} ->
        identities
        |> Enum.flat_map(&bond_rows(&1, responses[{:validator, &1}]))
        |> Consensus.upsert_validators()

      false ->
        :ok

      error ->
        Logger.debug(fn -> "Shinerium validators: shn_getValidator: #{inspect(error)}" end)
    end

    :ok
  end

  defp bond_rows(identity, %{} = bond), do: [bond_row(identity, bond)]
  defp bond_rows(_identity, _answer), do: []

  @doc """
  A validator's row from `shn_getValidator`'s answer.
  """
  @spec bond_row(Hash.Full.t(), map()) :: map()
  def bond_row(identity, bond) do
    %{
      identity: identity,
      ed_address_hash: cast!(Hash.Address, bond["edAddress"]),
      name: nonempty(bond["name"]),
      status: bond["status"],
      genesis: bond["genesis"],
      amount: bond["amount"] |> quantity!() |> wei(),
      bond_owner_hash: nonzero_address(bond["bondOwner"]),
      refund_address_hash: nonzero_address(bond["refundAddress"]),
      bls_hash: nonzero_hash(bond["blsHash"]),
      pq_hash: nonzero_hash(bond["pqHash"]),
      active_at: quantity!(bond["activeAt"]),
      exiting: bond["exiting"],
      release_at: bond["releaseAt"] |> quantity!() |> nonzero_time(),
      forced_exit: bond["forcedExit"],
      required: bond["required"] |> quantity!() |> wei(),
      shortfall: bond["shortfall"] |> quantity!() |> wei(),
      penalty: penalty(bond["penalty"]),
      penalty_box: penalty_box(bond["penaltyBox"]),
      bond_block_number: quantity!(bond["blockNumber"])
    }
  end

  defp penalty(%{} = penalty) do
    %{
      "reason" => penalty["reason"],
      "active" => penalty["active"],
      "awaiting_removal" => penalty["awaitingRemoval"],
      "until" => penalty["until"] |> quantity!() |> nonzero_time() |> iso8601(),
      "requires_rebond" => penalty["requiresRebond"]
    }
  end

  defp penalty(_), do: nil

  defp penalty_box(%{} = box) do
    %{
      "seat_from" => quantity!(box["seatFrom"]),
      "since" => quantity!(box["since"]),
      "strikes" => quantity!(box["strikes"]),
      "reason" => quantity!(box["reason"]),
      "reason_name" => nonempty(box["reasonName"]),
      "active" => box["active"],
      "epochs_left" => quantity!(box["epochsLeft"])
    }
  end

  defp penalty_box(_), do: nil

  defp request(id, method, params), do: EthereumJSONRPC.request(%{id: id, method: method, params: params})

  # EthereumJSONRPC takes integer ids; the requests' own keys are mapped to them.
  defp batch(args, requests) do
    keys = Enum.map(requests, & &1.id)
    indexed = requests |> Enum.with_index() |> Enum.map(fn {request, i} -> %{request | id: i} end)

    case EthereumJSONRPC.json_rpc(indexed, args) do
      {:ok, responses} ->
        by_index = Map.new(responses, fn response -> {response.id, Map.get(response, :result)} end)
        {:ok, keys |> Enum.with_index() |> Map.new(fn {key, i} -> {key, Map.get(by_index, i)} end)}

      error ->
        error
    end
  end

  defp call(args, method, params) do
    EthereumJSONRPC.json_rpc(EthereumJSONRPC.request(%{id: 0, method: method, params: params}), args)
  end

  defp integer_to_quantity(integer), do: "0x" <> Integer.to_string(integer, 16)

  defp quantity("0x" <> hex) do
    case Integer.parse(hex, 16) do
      {value, ""} -> {:ok, value}
      _ -> {:error, :quantity}
    end
  end

  defp quantity(value) when is_integer(value), do: {:ok, value}
  defp quantity(_), do: {:error, :quantity}

  defp quantity!(value) do
    case quantity(value) do
      {:ok, integer} -> integer
      _ -> nil
    end
  end

  defp time(seconds) when is_integer(seconds), do: DateTime.from_unix!(seconds * 1_000_000, :microsecond)
  defp time(value), do: value |> quantity!() |> then(&(&1 && time(&1)))

  defp wei(nil), do: nil
  defp wei(value), do: %Wei{value: Decimal.new(value)}

  defp nonzero_time(nil), do: nil
  defp nonzero_time(0), do: nil
  defp nonzero_time(seconds), do: time(seconds)

  defp iso8601(nil), do: nil
  defp iso8601(time), do: DateTime.to_iso8601(time)

  defp nonempty(""), do: nil
  defp nonempty(value), do: value

  defp nonzero_address("0x" <> zeros = address) when byte_size(zeros) == 40 do
    if zeros == String.duplicate("0", 40), do: nil, else: cast(Hash.Address, address)
  end

  defp nonzero_address(_), do: nil

  defp nonzero_hash("0x" <> zeros = hash) when byte_size(zeros) == 64 do
    if zeros == String.duplicate("0", 64), do: nil, else: cast(Hash.Full, hash)
  end

  defp nonzero_hash(_), do: nil

  defp cast(_type, nil), do: nil

  defp cast(type, value) do
    case type.cast(value) do
      {:ok, hash} -> hash
      :error -> nil
    end
  end

  defp cast!(type, value) do
    {:ok, hash} = type.cast(value)
    hash
  end
end
