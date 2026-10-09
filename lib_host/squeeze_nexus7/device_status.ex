defmodule SqueezeNexus7.DeviceStatus do
  @moduledoc """
  Stand-in for the device's status bar snapshot when running on a PC.
  """

  @spec read() :: map()
  def read do
    %{wifi: %{ssid: "host", signal: 80}, ip: "127.0.0.1", battery: %{percent: 76, charging?: true}}
  end
end
