defmodule SqueezeNexus7.ArtTest do
  use ExUnit.Case, async: true

  alias SqueezeNexus7.Art

  test "a stream uses its station logo, not the generic cover of its temporary coverid" do
    fields = %{
      "coverid" => "-94293400430992",
      "artwork_url" =>
        "/imageproxy/http%3A%2F%2Fcdn-radiotime-logos.tunein.com%2Fs9483q.png/image.png"
    }

    assert {"u-" <> _,
            "/imageproxy/http%3A%2F%2Fcdn-radiotime-logos.tunein.com%2Fs9483q.png/image_640x640.png"} =
             Art.source(fields)
  end

  test "a library track uses its cover" do
    assert {"c-0d3af9be", "/music/0d3af9be/cover_640x640"} =
             Art.source(%{"coverid" => "0d3af9be"})
  end
end
