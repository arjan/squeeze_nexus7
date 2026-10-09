defmodule SqueezeNexus7.Lms.ProtocolTest do
  use ExUnit.Case, async: true

  alias SqueezeNexus7.Lms.Protocol

  test "parses a library reply into items and a count" do
    line =
      "albums 0 2 tags%3Ala id%3A19 album%3ADe%20liedjes%20van%20Gonnie%20%26amp%3B%20vriendjes " <>
        "artist%3AAgeeth%20de%20Haan id%3A2 album%3AZachtjes count%3A2"

    {header, items, count} =
      line |> Protocol.decode() |> Enum.drop(4) |> Protocol.pairs() |> Protocol.items("id")

    assert header == %{}
    assert count == 2

    assert [
             %{
               "id" => "19",
               "album" => "De liedjes van Gonnie & vriendjes",
               "artist" => "Ageeth de Haan"
             },
             %{"id" => "2", "album" => "Zachtjes"}
           ] = items
  end

  test "parses the discovery reply" do
    reply = "ENAME\x13logitechmediaserverJSON\x049000CLIP\x049090"

    assert {:ok, %{"NAME" => "logitechmediaserver", "JSON" => "9000", "CLIP" => "9090"}} =
             Protocol.discovery_reply(reply)
  end

  test "splits items with fields in varying order where a key repeats" do
    pairs = [
      {"sort", "weight"},
      {"cmd", "presets"},
      {"name", "My Presets"},
      {"name", "Local Radio"},
      {"cmd", "local"},
      {"count", "2"}
    ]

    assert {[
              %{"cmd" => "presets", "name" => "My Presets"},
              %{"cmd" => "local", "name" => "Local Radio"}
            ], 2} =
             Protocol.items_by_repeat(pairs, ["sort"])
  end
end
