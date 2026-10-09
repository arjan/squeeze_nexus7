defmodule SqueezeNexus7.UI.StatusBar do
  @moduledoc """
  Top bar: Wi-Fi signal and SSID, IP address, music server and battery
  (with a bolt while charging). Ported from hello_nexus7's status bar.
  """
  use Emerge.UI

  alias SqueezeNexus7.UI.Components

  def view(device, server) do
    row(
      [
        width(fill()),
        height(px(72)),
        padding_xy(28, 0),
        spacing(18),
        Background.color(color(:slate, 800)),
        Font.size(24),
        Font.color(color(:slate, 300))
      ],
      [
        wifi_bars(device[:wifi]),
        el([center_y()], text(Components.fit(wifi_label(device[:wifi]), 20))),
        el([center_y(), Font.color(color(:slate, 500))], text(device[:ip] || "no IP")),
        el([width(fill())], none()),
        server_dot(server),
        el([center_y()], text(server_label(server))),
        el([width(px(8))], none()),
        battery_icon(device[:battery])
      ]
    )
  end

  # Four bars of increasing height; lit bars show signal strength.
  defp wifi_bars(wifi) do
    lit = if wifi, do: ceil(wifi.signal / 25), else: 0

    row(
      [center_y(), height(px(28)), spacing(4)],
      for bar <- 1..4 do
        el(
          [
            width(px(7)),
            height(px(4 + bar * 6)),
            align_bottom(),
            Border.rounded(2),
            Background.color(if bar <= lit, do: color(:emerald, 400), else: color(:slate, 600))
          ],
          none()
        )
      end
    )
  end

  defp wifi_label(nil), do: "Wi-Fi off"
  defp wifi_label(%{ssid: ssid}), do: ssid

  defp server_dot(server) do
    dot =
      case server do
        %{phase: :connected} -> color(:emerald, 400)
        %{phase: :connecting} -> color(:amber, 400)
        _ -> color(:rose, 500)
      end

    el(
      [center_y(), width(px(14)), height(px(14)), Border.rounded(7), Background.color(dot)],
      none()
    )
  end

  # Connected shows as a green dot only; the bar is too narrow for the name.
  defp server_label(%{phase: :connected}), do: ""
  defp server_label(%{phase: :connecting}), do: "connecting"
  defp server_label(_server), do: "no server"

  defp battery_icon(nil), do: none()

  defp battery_icon(%{percent: percent, charging?: charging?}) do
    level =
      cond do
        charging? -> color(:emerald, 400)
        percent <= 20 -> color(:rose, 500)
        true -> color(:slate, 200)
      end

    row([center_y(), spacing(2)], [
      el(
        [
          width(px(52)),
          height(px(26)),
          padding(3),
          Border.width(2),
          Border.color(color(:slate, 300)),
          Border.rounded(5)
        ] ++ bolt(charging?),
        el(
          [
            width(px(round(42 * percent / 100))),
            height(fill()),
            Border.rounded(2),
            Background.color(level)
          ],
          none()
        )
      ),
      el(
        [
          width(px(4)),
          height(px(10)),
          center_y(),
          Border.rounded(1),
          Background.color(color(:slate, 300))
        ],
        none()
      )
    ])
  end

  defp bolt(false), do: []

  defp bolt(true) do
    [
      Nearby.in_front(
        el(
          [center_x(), center_y()],
          svg([width(px(22)), height(px(22)), Svg.color(color(:amber, 300))], "icons/bolt.svg")
        )
      )
    ]
  end
end
