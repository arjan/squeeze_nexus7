defmodule SqueezeNexus7.UI.NowPlaying do
  @moduledoc """
  Cover, track, progress, transport and volume for this tablet's player.
  """
  use Emerge.UI
  use Solve.Lookup, :helpers

  import SqueezeNexus7.UI.Components

  @cover 520

  def view(%{known?: false}, _queue) do
    message("Waiting for this player to join the server…")
  end

  def view(player, queue) do
    column([width(fill()), height(fill()), padding_xy(48, 32), spacing(22)], [
      cover(player.art),
      row([width(fill()), spacing(16)], [
        column([width(fill()), spacing(10)], [
          el([Font.size(40), Font.bold()], text(fit(title(player), 26))),
          el(
            [Font.size(28), Font.color(color(:slate, 400))],
            text(fit(subtitle(player), 38))
          )
        ]),
        button([center_y(), Font.size(26)], queue, text("Queue"))
      ]),
      progress(player),
      transport(player),
      volume(player)
    ])
  end

  @doc "Full-screen notice, also used while the server isn't connected."
  def message(text) do
    el(
      [width(fill()), height(fill())],
      el([center_x(), center_y(), Font.size(30), Font.color(color(:slate, 400))], text(text))
    )
  end

  defp cover(nil) do
    el(
      [
        center_x(),
        width(px(@cover)),
        height(px(@cover)),
        Border.rounded(20),
        Background.color(color(:slate, 800))
      ],
      el([center_x(), center_y()], icon("note", 160, color(:slate, 600)))
    )
  end

  defp cover(path) do
    image(
      [center_x(), width(px(@cover)), height(px(@cover)), image_fit(:cover), Border.rounded(20)],
      {:path, path}
    )
  end

  defp title(%{has_track?: false}), do: "Nothing playing"
  defp title(player), do: player.title || "Unknown"

  # Radio streams report the station in remote_title, often also as the
  # artist ("Radio 538 102.1" and "Radio 538 102.1 (Top 40 & Pop Music)"), so
  # a part already contained in another one is left out.
  defp subtitle(player) do
    parts = Enum.reject([player.artist, player.album || player.remote_title], &(&1 in [nil, ""]))

    parts
    |> Enum.reject(fn part -> Enum.any?(parts, &(&1 != part and String.contains?(&1, part))) end)
    |> Enum.uniq()
    |> Enum.join(" — ")
  end

  defp progress(%{duration: duration} = player) when duration > 0 do
    column([width(fill()), spacing(4)], [
      slider(event(player, :seek), 0, duration, player.elapsed, color(:sky, 400)),
      row([width(fill()), Font.size(22), Font.color(color(:slate, 400))], [
        text(clock(player.elapsed)),
        el([align_right()], text(clock(duration)))
      ])
    ])
  end

  # A radio stream has no length or position worth showing.
  defp progress(_player), do: el([height(px(98))], none())

  # A radio stream has nothing to skip to.
  defp transport(%{remote?: true} = player) do
    row([center_x()], [play_pause(player)])
  end

  defp transport(player) do
    row([center_x(), spacing(56)], [
      round_button(event(player, :previous), 110, icon("previous", 48)),
      play_pause(player),
      round_button(event(player, :next), 110, icon("next", 48))
    ])
  end

  defp play_pause(player) do
    round_button(
      event(player, :toggle),
      150,
      icon(if(player.playing?, do: "pause", else: "play"), 72),
      color(:sky, 600)
    )
  end

  defp round_button(on_press, size, content, background \\ color(:slate, 700)) do
    button(
      [
        center_y(),
        width(px(size)),
        height(px(size)),
        padding(0),
        Border.rounded(div(size, 2)),
        Background.color(background)
      ],
      on_press,
      content
    )
  end

  defp volume(player) do
    row([width(fill()), spacing(20)], [
      el([center_y(), Font.size(24), Font.color(color(:slate, 400))], text("Vol")),
      slider(event(player, :volume), 0, 100, player.volume, color(:slate, 300)),
      el(
        [center_y(), width(px(56)), Font.size(24), Font.color(color(:slate, 400))],
        text("#{player.volume}")
      )
    ])
  end

  defp slider(on_change, min, max, value, fill_color) do
    Input.slider(
      [
        width(fill()),
        height(px(70)),
        Slider.config(
          min: min,
          max: max,
          track:
            el([height(px(12)), Background.color(color(:slate, 700)), Border.rounded(6)], none()),
          filled_track:
            el([height(px(12)), Background.color(fill_color), Border.rounded(6)], none()),
          thumb:
            el(
              [
                width(px(44)),
                height(px(44)),
                Background.color(color(:white)),
                Border.rounded(22)
              ],
              none()
            )
        ),
        Event.on_change(on_change)
      ],
      Kernel.min(value * 1.0, max * 1.0)
    )
  end
end
