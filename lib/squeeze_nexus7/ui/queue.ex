defmodule SqueezeNexus7.UI.Queue do
  @moduledoc """
  The play queue, opened from now playing: tap a track to play it, × removes
  it.
  """
  use Emerge.UI
  use Solve.Lookup, :helpers

  import SqueezeNexus7.UI.Components

  def view(queue, back) do
    column([width(fill()), height(fill()), padding_xy(32, 24), spacing(14)], [
      row([width(fill()), height(px(84)), spacing(20)], [
        button([width(px(110))], back, text("←")),
        el([center_y(), Font.size(34), Font.bold()], text("Queue")),
        el(
          [center_y(), Font.size(26), Font.color(color(:slate, 400))],
          text(tracks(queue.count))
        ),
        el([width(fill())], none()),
        button([Font.size(28)], if(queue.count > 0, do: event(queue, :clear)), text("Clear"))
      ]),
      column([width(fill()), height(fill()), spacing(6)], rows(queue)),
      pager(queue.offset, queue.page_size, queue.count, &event(queue, :page, &1))
    ])
  end

  defp tracks(1), do: "1 track"
  defp tracks(count), do: "#{count} tracks"

  defp rows(%{items: []}),
    do: [el([Font.size(26), Font.color(color(:slate, 500))], text("The queue is empty"))]

  defp rows(queue), do: Enum.map(queue.items, &item_row(queue, &1))

  defp item_row(queue, item) do
    current? = item.index == queue.current

    row(
      [
        width(fill()),
        height(px(84)),
        Border.rounded(14),
        Background.color(if current?, do: color(:sky, 900), else: color(:slate, 800))
      ],
      [
        Input.button(
          [
            width(fill()),
            height(fill()),
            padding_xy(24, 0),
            Border.rounded(14),
            Interactive.mouse_down([Background.color(color(:slate, 700))]),
            Event.on_press(event(queue, :jump, item.index))
          ],
          row([center_y(), width(fill()), height(fill()), spacing(18)], [
            el(
              [width(px(52)), center_y(), Font.size(24), Font.color(color(:slate, 500))],
              text("#{item.index + 1}")
            ),
            column([center_y(), spacing(6)], [
              el(
                [Font.size(28), if(current?, do: Font.bold(), else: Font.regular())],
                text(fit(item.title, 32))
              ),
              if(item.artist,
                do:
                  el([Font.size(21), Font.color(color(:slate, 400))], text(fit(item.artist, 40))),
                else: none()
              )
            ])
          ])
        ),
        el(
          [center_y(), padding_each(0, 10, 0, 0)],
          button(
            [width(px(84)), height(px(68)), padding(0)],
            event(queue, :remove, item.index),
            text("×")
          )
        )
      ]
    )
  end
end
