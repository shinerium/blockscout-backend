# SPDX-License-Identifier: LicenseRef-Blockscout
defmodule EthereumJSONRPC.Shinerium.RLP do
  @moduledoc """
  A small reader of RLP, for the Shinerium node's encodings the explorer reads:
  the system contracts' calldata (`Explorer.Chain.Shinerium.SystemCall`) and the
  quorum certificate in a block's `justify` (`EthereumJSONRPC.Shinerium.QuorumCertificate`).

  It is strict about lengths: an item must fit its input exactly. Items are
  `{:string, bytes}`, or `{:list, payload}` for a list inside the list read,
  which is not read further (`list/1` reads it when asked).
  """

  @type item :: {:string, binary()} | {:list, binary()}

  @doc """
  The items of the RLP list that is the whole input.

      iex> EthereumJSONRPC.Shinerium.RLP.list(<<0xC4, 0x01, 0x82, 0x01, 0x00>>)
      {:ok, [{:string, <<1>>}, {:string, <<1, 0>>}]}

      iex> EthereumJSONRPC.Shinerium.RLP.list(<<0xC3, 0x01, 0x82, 0x01>>)
      :error
  """
  @spec list(binary()) :: {:ok, [item()]} | :error
  def list(input) when is_binary(input) do
    case item(input) do
      {:ok, {:list, payload}, <<>>} -> items(payload, [])
      _ -> :error
    end
  end

  def list({:list, payload}), do: items(payload, [])
  def list(_), do: :error

  @doc """
  A uint64 as RLP holds it: big-endian, no leading zero, empty for zero.

      iex> EthereumJSONRPC.Shinerium.RLP.uint({:string, <<0x10, 0x0A>>})
      {:ok, 4106}

      iex> EthereumJSONRPC.Shinerium.RLP.uint({:string, <<0, 1>>})
      :error
  """
  @spec uint(item() | binary()) :: {:ok, non_neg_integer()} | :error
  def uint({:string, bytes}), do: uint(bytes)
  def uint(<<>>), do: {:ok, 0}
  def uint(<<0, _::binary>>), do: :error
  def uint(bytes) when is_binary(bytes) and byte_size(bytes) <= 8, do: {:ok, :binary.decode_unsigned(bytes)}
  def uint(_), do: :error

  defp items(<<>>, acc), do: {:ok, Enum.reverse(acc)}

  defp items(payload, acc) do
    case item(payload) do
      {:ok, item, rest} -> items(rest, [item | acc])
      :error -> :error
    end
  end

  defp item(<<byte, rest::binary>>) when byte < 0x80, do: {:ok, {:string, <<byte>>}, rest}
  defp item(<<prefix, rest::binary>>) when prefix <= 0xB7, do: take(:string, prefix - 0x80, rest)
  defp item(<<prefix, rest::binary>>) when prefix <= 0xBF, do: take_long(:string, prefix - 0xB7, rest)
  defp item(<<prefix, rest::binary>>) when prefix <= 0xF7, do: take(:list, prefix - 0xC0, rest)
  defp item(<<prefix, rest::binary>>), do: take_long(:list, prefix - 0xF7, rest)
  defp item(_), do: :error

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
