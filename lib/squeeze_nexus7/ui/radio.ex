defmodule SqueezeNexus7.UI.Radio do
  @moduledoc """
  Radio: Favourites as tiles (logo and name, tap to play, the playing one
  outlined; Edit turns taps into removal) and Browse as a list of sources
  and stations (tap to open or play, the star adds or removes a favourite).
  """
  use Emerge.UI
  use Solve.Lookup, :helpers

  import SqueezeNexus7.UI.Components

  @labels %{favorites: "Favourites", browse: "Browse"}
  @tile_height 228
  @logo 136
  @thumb 72

  def view(radio) do
    column([width(fill()), height(fill()), padding_xy(32, 24), spacing(16)], [
      sections(radio),
      header(radio),
      column([width(fill()), height(fill()), spacing(radio_spacing(radio))], content(radio)),
      pager(radio.offset, radio.page_size, radio.count, &event(radio, :page, &1))
    ])
  end

  defp radio_spacing(%{section: :favorites}), do: 16
  defp radio_spacing(_radio), do: 6

  defp sections(radio) do
    row(
      [width(fill()), spacing(12)],
      for section <- radio.sections do
        button(
          [
            width(fill()),
            height(px(72)),
            Font.size(26),
            Background.color(
              if section == radio.section, do: color(:sky, 700), else: color(:slate, 800)
            )
          ],
          event(radio, :section, section),
          text(@labels[section])
        )
      end
    )
  end

  defp header(radio) do
    row([width(fill()), height(px(84)), spacing(20)], [
      if(radio.depth > 1,
        do: button([width(px(110))], event(radio, :back), text("←")),
        else: none()
      ),
      el([center_y(), width(fill()), Font.size(34), Font.bold()], text(fit(radio.title, 24))),
      edit_button(radio)
    ])
  end

  defp edit_button(%{section: :favorites} = radio) do
    button(
      [
        Font.size(26),
        Background.color(if radio.editing?, do: color(:rose, 600), else: color(:slate, 700))
      ],
      event(radio, :edit),
      text(if radio.editing?, do: "Done", else: "Edit")
    )
  end

  defp edit_button(_radio), do: none()

  defp content(%{error: error}) when is_binary(error),
    do: [el([Font.size(26), Font.color(color(:rose, 400))], text(error))]

  defp content(%{items: [], section: :favorites}),
    do: [notice("No favourites yet. Star stations in Browse.")]

  defp content(%{items: []}), do: [notice("Nothing here")]

  defp content(%{section: :favorites} = radio) do
    radio.items
    |> Enum.with_index()
    |> Enum.chunk_every(2)
    |> Enum.map(fn pair ->
      row(
        [width(fill()), spacing(16)],
        Enum.map(pair, fn {item, i} -> tile(radio, item, i) end) ++ filler(pair)
      )
    end)
  end

  defp content(radio) do
    radio.items
    |> Enum.with_index()
    |> Enum.map(fn {item, i} -> browse_row(radio, item, i) end)
  end

  defp notice(message),
    do: el([Font.size(26), Font.color(color(:slate, 500))], text(message))

  # Keeps a lone last tile at half width.
  defp filler([_]), do: [el([width(fill())], none())]
  defp filler(_pair), do: []

  defp tile(radio, item, position) do
    {border, background} =
      cond do
        radio.editing? -> {color(:rose, 500), color(:slate, 800)}
        item.playing? -> {color(:sky, 400), color(:sky, 900)}
        true -> {color(:slate, 800), color(:slate, 800)}
      end

    action = if item.folder? and not radio.editing?, do: :open, else: :play

    Input.button(
      [
        width(fill()),
        height(px(@tile_height)),
        padding(14),
        Border.rounded(20),
        Border.width(4),
        Border.color(border),
        Background.color(background),
        Interactive.mouse_down([Background.color(color(:slate, 700))]),
        Event.on_press(event(radio, action, position))
      ],
      column([width(fill()), height(fill()), spacing(12)], [
        logo(item, @logo, center_x()),
        el(
          [
            center_x(),
            Font.size(24),
            Font.color(if radio.editing?, do: color(:rose, 300), else: color(:white)),
            if(item.playing?, do: Font.bold(), else: Font.regular())
          ],
          text(if radio.editing?, do: "Remove", else: fit(short_name(item.name), 24))
        )
      ])
    )
  end

  defp browse_row(radio, item, position) do
    row(
      [
        width(fill()),
        height(px(96)),
        spacing(12),
        Border.rounded(14),
        Background.color(if item.playing?, do: color(:sky, 900), else: color(:slate, 800))
      ],
      [
        Input.button(
          [
            width(fill()),
            height(fill()),
            padding_xy(12, 0),
            Border.rounded(14),
            Interactive.mouse_down([Background.color(color(:slate, 700))]),
            Event.on_press(event(radio, if(item.folder?, do: :open, else: :play), position))
          ],
          row([center_y(), spacing(18)], [
            logo(item, @thumb, center_y()),
            el([center_y(), Font.size(26)], text(fit(item.name, 30)))
          ])
        ),
        if item.playable? do
          el(
            [center_y(), padding_each(0, 10, 0, 0)],
            button(
              [
                width(px(84)),
                height(px(72)),
                padding(0)
              ],
              event(radio, :star, position),
              if(item.starred?,
                do: icon("star", 40, color(:amber, 300)),
                else: icon("star-outline", 40, color(:slate, 300))
              )
            )
          )
        else
          el(
            [
              center_y(),
              padding_each(0, 24, 0, 0),
              Font.size(36),
              Font.color(color(:slate, 500))
            ],
            text("›")
          )
        end
      ]
    )
  end

  # TuneIn names end in a frequency and genre: "Radio 538 102.1 (Top 40 & Pop Music)".
  defp short_name(name), do: String.replace(name, ~r/\s*\([^)]*\)\s*\z/, "")

  # Logos are often transparent, so they sit on a light card.
  defp logo(%{logo: path}, size, align) when is_binary(path) do
    el(
      [
        align,
        width(px(size)),
        height(px(size)),
        padding(div(size, 18)),
        Border.rounded(div(size, 9)),
        Background.color(color(:white))
      ],
      image([width(fill()), height(fill()), image_fit(:contain)], {:path, path})
    )
  end

  defp logo(item, size, align) do
    el(
      [
        align,
        width(px(size)),
        height(px(size)),
        Border.rounded(div(size, 9)),
        Background.color(color(:slate, 700))
      ],
      if item.folder? do
        el(
          [center_x(), center_y(), Font.size(div(size, 3)), Font.color(color(:slate, 400))],
          text("…")
        )
      else
        el([center_x(), center_y()], icon("note", div(size, 2), color(:slate, 400)))
      end
    )
  end
end
