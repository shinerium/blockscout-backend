# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule Explorer.Chain.Shinerium.SystemCall do
  @moduledoc """
  Names the operations of Shinerium's system contracts that take RLP input
  instead of ABI calls: the validator bond (`0x…0102`), the binary registry
  (`0x…0103`), the account keys (`0x…0106`) and the council (`0x…0107`).

  Each contract's input is the RLP list of the node's `Request` struct
  (core/validatorbond, core/binaryregistry, core/accountkeys and core/council of
  the node), whose first item is the operation's number. The rest of the list is
  read by position for a few fields worth showing. The input is read when a
  transaction is shown, so nothing is stored. An operation number the explorer
  does not know keeps a null name.
  """

  alias Explorer.Chain.{Data, Hash}

  @type t :: %{
          contract: String.t(),
          code: non_neg_integer(),
          name: String.t() | nil,
          identity: binary() | nil,
          proposal: non_neg_integer() | nil,
          kind: String.t() | nil,
          choice: String.t() | nil,
          scheme: non_neg_integer() | nil,
          policy: String.t() | nil,
          binary: binary() | nil,
          version: non_neg_integer() | nil
        }

  @contracts %{
    <<0::144, 0x01, 0x02>> => :bond,
    <<0::144, 0x01, 0x03>> => :registry,
    <<0::144, 0x01, 0x06>> => :account_keys,
    <<0::144, 0x01, 0x07>> => :council
  }

  # As `shn_systemContracts` names them.
  @contract_names %{
    bond: "ValidatorBond",
    registry: "BinaryRegistry",
    account_keys: "AccountKeys",
    council: "Council"
  }

  # The operations' numbers of the node, named as the node's constants are, in
  # the case of an ABI function name.
  @operations %{
    bond: %{
      1 => "deposit",
      2 => "requestExit",
      3 => "beginRelease",
      4 => "withdraw",
      5 => "reportConflict",
      6 => "signingReset",
      7 => "setName",
      8 => "transferOwner",
      9 => "topUp"
    },
    registry: %{1 => "approve", 2 => "require", 3 => "attest"},
    account_keys: %{1 => "register", 2 => "rotate", 3 => "setPolicy", 4 => "clear"},
    council: %{1 => "propose", 2 => "vote", 3 => "execute", 4 => "object"}
  }

  @council_kinds %{1 => "transfer", 2 => "signal", 3 => "recall", 4 => "collateral"}
  @council_choices %{1 => "yes", 2 => "no", 3 => "abstain"}
  @policies %{0 => "none", 1 => "optional", 2 => "required", 3 => "pq-only"}

  @empty %{
    identity: nil,
    proposal: nil,
    kind: nil,
    choice: nil,
    scheme: nil,
    policy: nil,
    binary: nil,
    version: nil
  }

  @doc """
  The operation a transaction's input asks of a system contract, or nil when the
  transaction goes elsewhere or its input is no RLP list that starts with an
  operation number.

  The fields that an operation does not carry are nil: `identity` is the
  Ed25519 key that acts (the bond's identity, the council member that signs, the
  registry's signer), `proposal` the council's proposal that a vote, an
  execution or an objection names, `kind` a proposal's kind, `choice` a vote's,
  `scheme` the post-quantum scheme of a key registered or rotated, `policy` the
  account's policy that a registration or a change of policy sets, `binary` the
  SHA-256 of the node binary that the registry approves or that a validator
  attests, and `version` the version an approval gives or a requirement sets.
  """
  @spec decode(Hash.Address.t() | nil, Data.t() | nil) :: t() | nil
  def decode(%Hash{bytes: address}, %Data{bytes: input}) when is_map_key(@contracts, address) do
    contract = Map.fetch!(@contracts, address)

    with {:ok, [{:string, op} | _] = items} <- rlp_list(input),
         {:ok, code} <- uint(op) do
      operation(contract, code, items)
    else
      _ -> nil
    end
  end

  def decode(_, _), do: nil

  defp operation(contract, code, items) do
    base = Map.merge(@empty, %{contract: @contract_names[contract], code: code, name: @operations[contract][code]})

    if base.name do
      Map.merge(base, details(contract, code, items))
    else
      base
    end
  end

  # core/validatorbond: [Op, EdPublic, BlsPublic, Withdrawal, Nonce, Proof, BlsProof,
  # Commitment?, Name?, PQPublic?, NewOwner?]
  defp details(:bond, _code, items), do: %{identity: bytes_at(items, 1, 32)}

  # core/council: [Op, Identity, PQPublic, Nonce, Proposal, Kind, Account, Target, Amount,
  # Data, Choice, Rationale, Proof]
  defp details(:council, code, items) do
    %{
      identity: bytes_at(items, 1, 32),
      proposal: if(code in [2, 3, 4], do: uint_at(items, 4)),
      kind: if(code == 1, do: lookup(@council_kinds, uint_at(items, 5))),
      choice: if(code == 2, do: lookup(@council_choices, uint_at(items, 10)))
    }
  end

  # core/accountkeys: [Op, Scheme, PublicKey, Policy, Proof]
  defp details(:account_keys, code, items) do
    %{
      scheme: if(code in [1, 2], do: uint_at(items, 1)),
      policy: if(code in [1, 3], do: lookup(@policies, uint_at(items, 3)))
    }
  end

  # core/binaryregistry: [Op, Binary, Version, From, Signer, Sequence, Signature]
  defp details(:registry, code, items) do
    %{
      identity: bytes_at(items, 4, 32),
      binary: if(code in [1, 3], do: bytes_at(items, 1, 32)),
      version: if(code in [1, 2], do: uint_at(items, 2))
    }
  end

  defp lookup(_map, nil), do: nil
  defp lookup(map, key), do: Map.get(map, key)

  defp bytes_at(items, index, size) do
    case Enum.at(items, index) do
      {:string, <<_::binary-size(^size)>> = bytes} -> bytes
      _ -> nil
    end
  end

  defp uint_at(items, index) do
    with {:string, bytes} <- Enum.at(items, index),
         {:ok, value} <- uint(bytes) do
      value
    else
      _ -> nil
    end
  end

  # A uint64 as RLP holds it: big-endian, no leading zero, empty for zero.
  defp uint(<<>>), do: {:ok, 0}
  defp uint(<<0, _::binary>>), do: :error
  defp uint(bytes) when byte_size(bytes) <= 8, do: {:ok, :binary.decode_unsigned(bytes)}
  defp uint(_), do: :error

  # The items of the RLP list that is the whole input: {:string, bytes}, or
  # {:list, payload} for a list within it, which is not read further.
  defp rlp_list(input) do
    case rlp_item(input) do
      {:ok, {:list, payload}, <<>>} -> rlp_items(payload, [])
      _ -> :error
    end
  end

  defp rlp_items(<<>>, items), do: {:ok, Enum.reverse(items)}

  defp rlp_items(payload, items) do
    case rlp_item(payload) do
      {:ok, item, rest} -> rlp_items(rest, [item | items])
      :error -> :error
    end
  end

  defp rlp_item(<<byte, rest::binary>>) when byte < 0x80, do: {:ok, {:string, <<byte>>}, rest}
  defp rlp_item(<<prefix, rest::binary>>) when prefix <= 0xB7, do: take(:string, prefix - 0x80, rest)
  defp rlp_item(<<prefix, rest::binary>>) when prefix <= 0xBF, do: take_long(:string, prefix - 0xB7, rest)
  defp rlp_item(<<prefix, rest::binary>>) when prefix <= 0xF7, do: take(:list, prefix - 0xC0, rest)
  defp rlp_item(<<prefix, rest::binary>>), do: take_long(:list, prefix - 0xF7, rest)
  defp rlp_item(_), do: :error

  defp take(kind, size, rest) do
    case rest do
      <<payload::binary-size(^size), rest::binary>> -> {:ok, {kind, payload}, rest}
      _ -> :error
    end
  end

  defp take_long(kind, size_bytes, rest) do
    case rest do
      <<size::unsigned-big-integer-size(^size_bytes)-unit(8), rest::binary>> -> take(kind, size, rest)
      _ -> :error
    end
  end
end
