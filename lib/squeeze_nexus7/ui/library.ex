defmodule SqueezeNexus7.UI.Library do
  @moduledoc """
  Section tabs, a back button and title, one page of items and a pager.
  Tapping an item opens it; ▶ plays it now, + adds it to the queue.
  """
  use Emerge.UI
  use Solve.Lookup, :helpers

  import SqueezeNexus7.UI.Components

  @labels %{artists: "Artists", albums: "Albums", playlists: "Playlists"}

  def view(library) do
    column([width(fill()), height(fill()), padding_xy(32, 24), spacing(14)], [
      sections(library),
      header(library),
      column([width(fill()), height(fill()), spacing(6)], rows(library)),
      pager(library.offset, library.page_size, library.count, &event(library, :page, &1))
    ])
  end

  defp sections(library) do
    row(
      [width(fill()), spacing(12)],
      for section <- library.sections do
        selected? = section == library.section

        button(
          [
            width(fill()),
            height(px(72)),
            padding_xy(8, 0),
            Font.size(24),
            Background.color(if selected?, do: color(:sky, 700), else: color(:slate, 800))
          ],
          event(library, :section, section),
          text(@labels[section])
        )
      end
    )
  end

  defp header(library) do
    row([width(fill()), height(px(84)), spacing(20)], [
      if library.depth > 1 do
        button([width(px(110))], event(library, :back), text("←"))
      else
        none()
      end,
      el([center_y(), Font.size(34), Font.bold()], text(fit(library.title, 30)))
    ])
  end

  defp rows(%{error: error}) when is_binary(error),
    do: [el([Font.size(26), Font.color(color(:rose, 400))], text(error))]

  defp rows(%{items: []}),
    do: [el([Font.size(26), Font.color(color(:slate, 500))], text("Nothing here"))]

  defp rows(library) do
    library.items
    |> Enum.with_index()
    |> Enum.map(fn {item, position} -> item_row(library, item, position) end)
  end

  defp item_row(library, item, position) do
    row(
      [
        width(fill()),
        height(px(84)),
        spacing(12),
        Border.rounded(14),
        Background.color(color(:slate, 800))
      ],
      [
        Input.button(
          [
            width(fill()),
            height(fill()),
            padding_xy(24, 0),
            Border.rounded(14),
            Interactive.mouse_down([Background.color(color(:slate, 700))])
          ] ++ if(item.open?, do: [Event.on_press(event(library, :open, position))], else: []),
          column([center_y(), spacing(6)], [
            el([Font.size(28)], text(fit(item.label, 34))),
            if(item.detail,
              do: el([Font.size(21), Font.color(color(:slate, 400))], text(fit(item.detail, 44))),
              else: none()
            )
          ])
        ),
        if item.play? do
          row([center_y(), spacing(10), padding_each(0, 10, 0, 0)], [
            button(
              [width(px(84)), height(px(68)), padding(0)],
              event(library, :add, position),
              text("+")
            ),
            button(
              [width(px(84)), height(px(68)), padding(0), Background.color(color(:sky, 700))],
              event(library, :play, position),
              icon("play", 32)
            )
          ])
        else
          none()
        end
      ]
    )
  end
end
