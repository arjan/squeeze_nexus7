defmodule SqueezeNexus7.State.Device do
  @moduledoc """
  Wi-Fi, IP address and battery for the status bar, polled every two
  seconds.
  """
  use Solve.Controller, events: []

  alias SqueezeNexus7.DeviceStatus

  @interval 2_000

  @impl true
  def init(_params, _dependencies) do
    Process.send_after(self(), :poll, @interval)
    DeviceStatus.read()
  end

  def handle_info(:poll, _state) do
    Process.send_after(self(), :poll, @interval)
    DeviceStatus.read()
  end
end
