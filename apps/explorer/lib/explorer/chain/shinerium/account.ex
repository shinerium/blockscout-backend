# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Explorer.Chain.Shinerium.Account do
  @moduledoc """
  An account's post-quantum key and vesting at the latest block, as the node gives
  them (`shn_getAccountKey` and `shn_getVesting`; docs/eth-rpc.md of the node).

  Neither is stored: both change with the account's operations and, for vesting,
  with time, so they are read from the node when asked for. A part the node does not
  give (an error, or a node without the method) is nil.
  """

  require Logger

  alias Explorer.Chain.Hash

  @type account_key :: %{
          policy: String.t(),
          scheme: non_neg_integer() | nil,
          version: non_neg_integer(),
          changed_at_block: non_neg_integer(),
          key_hash: String.t() | nil,
          verifiable: boolean()
        }

  @type vesting_record :: %{
          amount: non_neg_integer(),
          start: DateTime.t() | nil,
          cliff: DateTime.t() | nil,
          end: DateTime.t() | nil,
          step: non_neg_integer(),
          pool: boolean()
        }

  @type vesting :: %{
          locked_until: DateTime.t() | nil,
          wholly_locked: boolean(),
          locked: non_neg_integer() | nil,
          spendable: non_neg_integer() | nil,
          vested: non_neg_integer() | nil,
          next_vest: DateTime.t() | nil,
          record: vesting_record() | nil
        }

  @type t :: %{account_key: account_key() | nil, vesting: vesting() | nil}

  @zero_hash "0x" <> String.duplicate("0", 64)

  @doc """
  The account's key and vesting. `scheme` is nil without a key, `locked_until` nil
  without a time lock, `vested` and `next_vest` nil without a vesting record (and
  `next_vest` also once all of it has vested).
  """
  @spec fetch(Hash.Address.t()) :: t()
  def fetch(%Hash{} = address_hash) do
    address = to_string(address_hash)

    %{
      account_key: address |> call("shn_getAccountKey") |> account_key(),
      vesting: address |> call("shn_getVesting") |> vesting()
    }
  end

  defp call(address, method) do
    request = EthereumJSONRPC.request(%{id: 0, method: method, params: [address, "latest"]})

    case EthereumJSONRPC.json_rpc(request, Application.get_env(:explorer, :json_rpc_named_arguments)) do
      {:ok, %{} = result} ->
        result

      {:ok, _} ->
        nil

      {:error, reason} ->
        Logger.warning("Shinerium account: #{method} of #{address} failed: #{inspect(reason)}")
        nil
    end
  end

  defp account_key(%{"policy" => policy} = result) when is_binary(policy) do
    %{
      policy: policy,
      scheme: nonzero(quantity(result["scheme"])),
      version: quantity(result["version"]) || 0,
      changed_at_block: quantity(result["changedAt"]) || 0,
      key_hash: nonzero_hash(result["keyHash"]),
      verifiable: result["verifiable"] == true
    }
  end

  defp account_key(_), do: nil

  defp vesting(%{"spendable" => _} = result) do
    %{
      locked_until: time(result["lockedUntil"]),
      wholly_locked: result["whollyLocked"] == true,
      locked: quantity(result["locked"]),
      spendable: quantity(result["spendable"]),
      vested: quantity(result["vested"]),
      next_vest: time(result["nextVest"]),
      record: record(result["record"])
    }
  end

  defp vesting(_), do: nil

  defp record(%{} = record) do
    %{
      amount: quantity(record["amount"]) || 0,
      start: time(record["start"]),
      cliff: time(record["cliff"]),
      end: time(record["end"]),
      step: quantity(record["step"]) || 0,
      pool: record["pool"] == true
    }
  end

  defp record(_), do: nil

  defp quantity("0x" <> _ = hex), do: EthereumJSONRPC.quantity_to_integer(hex)
  defp quantity(_), do: nil

  defp nonzero(0), do: nil
  defp nonzero(value), do: value

  defp nonzero_hash(@zero_hash), do: nil
  defp nonzero_hash("0x" <> _ = hash), do: String.downcase(hash)
  defp nonzero_hash(_), do: nil

  defp time(hex) do
    case quantity(hex) do
      nil -> nil
      0 -> nil
      seconds -> DateTime.from_unix!(seconds)
    end
  end
end
