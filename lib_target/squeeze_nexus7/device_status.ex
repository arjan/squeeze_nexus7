defmodule SqueezeNexus7.DeviceStatus do
  @moduledoc """
  Snapshot of what the status bar shows: Wi-Fi, IP address and battery.
  """

  @battery "/sys/class/power_supply/bq27541-0"

  @type t :: %{
          wifi: nil | %{ssid: String.t(), signal: 0..100},
          ip: nil | String.t(),
          battery: nil | %{percent: 0..100, charging?: boolean()}
        }

  @spec read() :: t()
  def read do
    %{wifi: wifi(), ip: ip_address(), battery: battery()}
  end

  defp wifi do
    with :internet <- VintageNet.get(["interface", "wlan0", "connection"]) |> connected(),
         %{ssid: ssid, signal_percent: signal} <-
           VintageNet.get(["interface", "wlan0", "wifi", "current_ap"]) do
      %{ssid: ssid, signal: signal}
    else
      _ -> nil
    end
  end

  defp connected(status) when status in [:internet, :lan], do: :internet
  defp connected(_status), do: :offline

  # Prefers Wi-Fi, then wired, then the USB link.
  defp ip_address do
    ["wlan0", "eth0", "usb0"]
    |> Enum.find_value(fn ifname ->
      VintageNet.get(["interface", ifname, "addresses"], [])
      |> Enum.find_value(fn
        %{family: :inet, address: address} -> address |> :inet.ntoa() |> to_string()
        _ -> nil
      end)
    end)
  end

  defp battery do
    with {:ok, capacity} <- read_int("capacity"),
         {:ok, current} <- read_int("current_now") do
      # The gauge reports current into the battery as positive.
      %{percent: capacity, charging?: current > 0}
    else
      _ -> nil
    end
  end

  defp read_int(name) do
    with {:ok, text} <- File.read(Path.join(@battery, name)),
         {value, _} <- Integer.parse(String.trim(text)) do
      {:ok, value}
    else
      _ -> :error
    end
  end
end
