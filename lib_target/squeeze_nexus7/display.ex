defmodule SqueezeNexus7.Display do
  @moduledoc """
  Device display glue: frames go to the KMS presenter, touches come from the
  touchscreen.
  """

  alias SqueezeNexus7.Display.FrameSink

  def headless_opts do
    sink = Process.whereis(FrameSink) || raise "frame sink is not running"
    [target: sink, pixel_format: :bgra8888, partial: true]
  end

  # The viewport holds the sink's pid and the touch reader holds the
  # viewport's renderer, so a crash restarts everything after it.
  def children do
    [FrameSink, {SqueezeNexus7.UI.Root, name: SqueezeNexus7.UI.Root}, SqueezeNexus7.Input.Touch]
  end
end
