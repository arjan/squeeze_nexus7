defmodule SqueezeNexus7.Display.Drm do
  @moduledoc """
  Minimal KMS presenter: two dumb buffers (XRGB8888) with page flipping and a
  CPU mirror, so partial frames can be staged and shown with one flip per
  vsync. Implemented in `c_src/drm_nif.c`.
  """
  @on_load :load_nif

  def load_nif do
    :erlang.load_nif(~c"#{:code.priv_dir(:squeeze_nexus7)}/drm_nif", 0)
  end

  @doc "Takes over the display. Returns `{:ok, display, {width, height, pitch, refresh_hz}}`."
  def open(_card_path), do: :erlang.nif_error(:not_loaded)

  @doc "Copies a BGRA rectangle into the mirror; shown on the next `commit/1`."
  def stage_region(_display, _bgra, _x, _y, _w, _h), do: :erlang.nif_error(:not_loaded)

  @doc "Updates the back buffer from the mirror and flips to it (waits for vsync)."
  def commit(_display), do: :erlang.nif_error(:not_loaded)

  @doc "Restores the console and releases the display."
  def close(_display), do: :erlang.nif_error(:not_loaded)
end
