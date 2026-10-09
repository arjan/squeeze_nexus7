defmodule SqueezeNexus7.UI.Components do
  @moduledoc """
  Small building blocks shared by the screens. Touch targets are at least
  80px; text is cut to fit because Emerge doesn't clip text.
  """
  use Emerge.UI

  @doc "A button with a label or icon; `on_press` is a Solve event (or nil to disable it)."
  def button(attrs, on_press, content) do
    defaults = [
      height(px(84)),
      padding_xy(24, 0),
      Font.size(36),
      Border.rounded(16),
      Background.color(color(:slate, 700)),
      Interactive.mouse_down([Background.color(color(:slate, 500))])
    ]

    # Attributes given by the caller replace the defaults of the same kind.
    defaults = Enum.reject(defaults, fn {key, _} -> List.keymember?(attrs, key, 0) end)
    Input.button(defaults ++ press(on_press) ++ attrs, el([center_x(), center_y()], content))
  end

  defp press(nil), do: [Transform.alpha(0.35)]
  defp press(event), do: [Event.on_press(event)]

  @doc "A tinted SVG icon from priv/icons."
  def icon(name, size, tint \\ color(:white)) do
    svg([width(px(size)), height(px(size)), Svg.color(tint)], "icons/#{name}.svg")
  end

  @doc "‹ 1–8 of 120 › pager below a list."
  def pager(offset, page_size, count, on_page) do
    last = Kernel.min(offset + page_size, count)

    row([width(fill()), height(px(96)), spacing(16)], [
      button([width(px(140))], if(offset > 0, do: on_page.(-1)), text("‹")),
      el(
        [width(fill()), center_y(), Font.center(), Font.size(26), Font.color(color(:slate, 400))],
        text(if count == 0, do: "", else: "#{offset + 1}–#{last} of #{count}")
      ),
      button([width(px(140))], if(last < count, do: on_page.(1)), text("›"))
    ])
  end

  @doc "Cuts `text` to `max` characters with an ellipsis."
  def fit(nil, _max), do: ""

  def fit(text, max) do
    if String.length(text) > max, do: String.slice(text, 0, max - 1) <> "…", else: text
  end

  @doc "Formats seconds as m:ss."
  def clock(seconds) when is_number(seconds) do
    total = trunc(seconds)
    "#{div(total, 60)}:#{total |> rem(60) |> Integer.to_string() |> String.pad_leading(2, "0")}"
  end

  def clock(_seconds), do: "0:00"
end
