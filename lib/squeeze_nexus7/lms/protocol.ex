defmodule SqueezeNexus7.Lms.Protocol do
  @moduledoc """
  Encoding and parsing for the LMS command line interface (port 9090) and the
  UDP discovery reply (port 3483).

  A CLI line is a list of space-separated, URL-encoded tokens. Replies echo the
  command tokens and then add `key:value` tokens; repeated keys form a list of
  items, each starting with the same key (`id` for library queries,
  `playlist index` for the queue in `status`).
  """

  @doc "Encodes command tokens into one CLI line."
  @spec encode([term()]) :: iodata()
  def encode(tokens) do
    [Enum.map_join(tokens, " ", &escape/1), ?\n]
  end

  defp escape(token), do: token |> to_string() |> URI.encode(&URI.char_unreserved?/1)

  @doc "Splits a CLI line into decoded tokens."
  @spec decode(binary()) :: [String.t()]
  def decode(line) do
    line
    |> String.trim_trailing()
    |> String.split(" ", trim: true)
    |> Enum.map(&URI.decode/1)
  end

  @doc "Turns `key:value` tokens into pairs, skipping tokens without a colon."
  @spec pairs([String.t()]) :: [{String.t(), String.t()}]
  def pairs(tokens) do
    for token <- tokens, [key, value] <- [String.split(token, ":", parts: 2)] do
      {key, unescape_html(value)}
    end
  end

  @doc """
  Splits reply pairs into the fields before the first item, the items (a new
  one starts at every `start_key`) and the total `count`.
  """
  @spec items([{String.t(), String.t()}], String.t()) ::
          {map(), [map()], non_neg_integer() | nil}
  def items(pairs, start_key) do
    {count, pairs} = take_count(pairs)
    {header, rest} = Enum.split_while(pairs, fn {key, _} -> key != start_key end)

    items =
      rest
      |> Enum.chunk_while(
        [],
        fn
          {^start_key, _} = pair, [] -> {:cont, [pair]}
          {^start_key, _} = pair, acc -> {:cont, Map.new(acc), [pair]}
          pair, acc -> {:cont, [pair | acc]}
        end,
        fn
          [] -> {:cont, []}
          acc -> {:cont, Map.new(acc), []}
        end
      )

    {Map.new(header), items, count}
  end

  @doc """
  Like `items/2` for replies whose items list their fields in varying order
  (`radios`): a new item starts whenever a key repeats.
  """
  @spec items_by_repeat([{String.t(), String.t()}], [String.t()]) ::
          {[map()], non_neg_integer() | nil}
  def items_by_repeat(pairs, skip_keys \\ []) do
    {count, pairs} = take_count(pairs)

    items =
      pairs
      |> Enum.reject(fn {key, _} -> key in skip_keys end)
      |> Enum.reduce([], fn
        {key, value}, [current | done] when not is_map_key(current, key) ->
          [Map.put(current, key, value) | done]

        {key, value}, done ->
          [%{key => value} | done]
      end)
      |> Enum.reverse()

    {items, count}
  end

  defp take_count(pairs) do
    case List.keytake(pairs, "count", 0) do
      {{"count", count}, rest} -> {String.to_integer(count), rest}
      nil -> {nil, pairs}
    end
  end

  @doc """
  Parses a discovery reply: `E` followed by fields of a 4-byte tag, a length
  byte and the value.
  """
  @spec discovery_reply(binary()) :: {:ok, %{String.t() => String.t()}} | :error
  def discovery_reply(<<"E", fields::binary>>), do: tlv(fields, %{})
  def discovery_reply(_other), do: :error

  defp tlv(<<>>, acc), do: {:ok, acc}

  defp tlv(<<tag::binary-size(4), len, value::binary-size(len), rest::binary>>, acc),
    do: tlv(rest, Map.put(acc, tag, value))

  defp tlv(_malformed, _acc), do: :error

  @doc "The discovery request asking for the server name and its ports."
  @spec discovery_request() :: binary()
  def discovery_request, do: "eNAME\0JSON\0CLIP\0VERS\0"

  # LMS escapes some names (album titles) as HTML.
  defp unescape_html(value) do
    if String.contains?(value, "&") do
      value
      |> String.replace("&lt;", "<")
      |> String.replace("&gt;", ">")
      |> String.replace("&quot;", "\"")
      |> String.replace("&#39;", "'")
      |> String.replace("&amp;", "&")
    else
      value
    end
  end
end
