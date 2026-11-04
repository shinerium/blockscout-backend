# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Explorer.Chain.Shinerium.AddressNames do
  @moduledoc """
  Names a Shinerium chain's protocol and genesis accounts that are no contracts:
  the epoch's reward pot, the support node fund, the ecosystem fund, the
  treasury's accounts and the genesis allocation's labelled accounts. (The
  system contracts get their names as verified contracts, from
  `PRECOMPILED_CONTRACTS_CONFIG_PATH`.)

  The names come from a JSON file, `SHINERIUM_ADDRESS_NAMES_PATH`, a list of
  `{"address": "0x…", "name": "…"}` that explorer-ops' `system-contracts.py`
  writes from the node and the genesis file. Each becomes its account's primary
  name, which the API gives as the address's `name`. The file is read once,
  after the start (`SHINERIUM_ADDRESS_NAMES_DELAY`, as the genesis import).
  """

  use GenServer

  require Logger

  alias Ecto.Multi
  alias Explorer.Chain.{Address, Hash}
  alias Explorer.Chain.Address.Name
  alias Explorer.Repo

  @max_name_length 255

  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(_) do
    Process.send_after(self(), :import, config(:delay) || :timer.seconds(20))
    {:ok, %{}}
  end

  @impl GenServer
  def handle_info(:import, state) do
    case config(:path) do
      nil -> :ok
      path -> import_file(path)
    end

    {:noreply, state}
  end

  @doc """
  Reads the names file at `path` and makes each name its account's primary
  name. Returns the number of accounts named, or an error for an unreadable
  file. An entry with an invalid address or an empty name is skipped.
  """
  @spec import_file(Path.t()) :: {:ok, non_neg_integer()} | {:error, term()}
  def import_file(path) do
    with {:ok, body} <- File.read(path),
         {:ok, entries} when is_list(entries) <- JSON.decode(body) do
      named = Enum.count(entries, &(import_entry(&1) == :ok))
      Logger.info("Shinerium address names: #{named} of #{length(entries)} accounts named from #{path}.")
      {:ok, named}
    else
      {:ok, _} ->
        Logger.warning("Shinerium address names: #{path} is not a list.")
        {:error, :not_a_list}

      {:error, reason} = error ->
        Logger.warning("Shinerium address names: cannot read #{path}: #{inspect(reason)}.")
        error
    end
  end

  @doc """
  Makes `name` the primary name of the account at `address`, an address string.
  Returns `:ok`, `:unchanged` when it is already, or `:skipped` for an invalid
  entry.
  """
  @spec import_entry(map()) :: :ok | :unchanged | :skipped
  def import_entry(%{"address" => address, "name" => name}) when is_binary(address) and is_binary(name) do
    name = name |> String.trim() |> String.slice(0, @max_name_length)

    with true <- name != "",
         {:ok, hash} <- Hash.Address.cast(address) do
      if primary_name(hash) == name, do: :unchanged, else: name_account(hash, name)
    else
      _ -> :skipped
    end
  end

  def import_entry(_), do: :skipped

  defp name_account(hash, name) do
    now = DateTime.utc_now()

    Multi.new()
    |> Multi.run(:address, fn repo, _ ->
      {count, _} =
        repo.insert_all(Address, [%{hash: hash, inserted_at: now, updated_at: now}],
          on_conflict: :nothing,
          conflict_target: :hash
        )

      {:ok, count}
    end)
    |> Multi.run(:clear, fn repo, _ -> Name.clear_primary_address_names(repo, hash) end)
    |> Multi.run(:name, fn repo, _ ->
      %Name{}
      |> Name.changeset(%{address_hash: hash, name: name, primary: true})
      |> repo.insert(
        on_conflict: [set: [primary: true, updated_at: now]],
        conflict_target: [:address_hash, :name]
      )
    end)
    |> Repo.transaction()
    |> case do
      {:ok, _} ->
        :ok

      {:error, step, reason, _} ->
        Logger.warning("Shinerium address names: #{Hash.to_string(hash)} not named (#{step}): #{inspect(reason)}.")
        :skipped
    end
  end

  defp primary_name(hash) do
    import Ecto.Query, only: [from: 2]

    Repo.one(
      from(name in Name,
        where: name.address_hash == ^hash and name.primary == true,
        select: name.name,
        limit: 1
      )
    )
  end

  defp config(key), do: Application.get_env(:explorer, __MODULE__, [])[key]
end
