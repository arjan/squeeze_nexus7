defmodule SqueezeNexus7.UI.Root do
  @moduledoc """
  The viewport: status bar, the current screen and the tab bar.

  Rendered headless on the CPU at the panel's size; `SqueezeNexus7.Display`
  decides where frames go (the KMS presenter on the device).
  """
  use Emerge
  use Solve.Lookup

  alias SqueezeNexus7.{Art, Display, State}
  alias SqueezeNexus7.UI.{Components, Library, NowPlaying, Queue, Radio, StatusBar}

  @width 800
  @height 1280
  @tabs [radio: "Radio", now_playing: "Now Playing", library: "Library"]

  @impl Viewport
  def mount(opts) do
    {:ok,
     Keyword.merge(
       [
         otp_app: :squeeze_nexus7,
         backend: :headless,
         rendering_api: :raster,
         width: @width,
         height: @height,
         headless: Display.headless_opts(),
         assets: [
           runtime_paths: [enabled: true, allowlist: [Art.dir()], follow_symlinks: false],
           # Covers are the only large images; a few are enough on 1 GB of RAM.
           cache: [max_entries: 32, max_bytes: 24_000_000]
         ]
       ],
       opts
     )}
  end

  @impl Viewport
  def render do
    nav = solve(State, :nav)

    column(
      [
        width(px(@width)),
        height(px(@height)),
        Background.color(color(:slate, 900)),
        Font.color(color(:white))
      ] ++ power_dialog(solve(State, :power)),
      [
        StatusBar.view(solve(State, :device) || %{}, solve(State, :server)),
        screen(nav),
        tab_bar(nav)
      ]
    )
  end

  defp screen(nav) do
    case {nav && nav.current, solve(State, :server)} do
      {_, %{phase: :searching}} ->
        NowPlaying.message("Searching for the music server…")

      {_, %{phase: :connecting, name: name}} ->
        NowPlaying.message("Connecting to #{name}…")

      {:radio, _} ->
        loaded(solve(State, :radio), &Radio.view/1)

      {:library, _} ->
        loaded(solve(State, :library), &Library.view/1)

      {:queue, _} ->
        loaded(solve(State, :queue), &Queue.view(&1, event(nav, :show, :now_playing)))

      _ ->
        loaded(solve(State, :player), &NowPlaying.view(&1, event(nav, :show, :queue)))
    end
  end

  defp power_dialog(%{phase: :idle}), do: []
  defp power_dialog(nil), do: []

  defp power_dialog(power) do
    card =
      case power.phase do
        :confirm ->
          column(
            [
              center_x(),
              center_y(),
              width(px(600)),
              padding(40),
              spacing(32),
              Border.rounded(28),
              Background.color(color(:slate, 800))
            ],
            [
              el([Font.size(38), Font.bold()], text("Shut down the tablet?")),
              el([Font.size(26), Font.color(color(:slate, 400))], text("Playback is paused.")),
              row([width(fill()), spacing(24)], [
                Components.button(
                  [width(fill()), Font.size(30)],
                  event(power, :cancel),
                  text("Cancel")
                ),
                Components.button(
                  [width(fill()), Font.size(30), Background.color(color(:rose, 600))],
                  event(power, :confirm),
                  text("Shut down")
                )
              ])
            ]
          )

        :shutting_down ->
          el(
            [
              center_x(),
              center_y(),
              padding(48),
              Border.rounded(28),
              Background.color(color(:slate, 800)),
              Font.size(34)
            ],
            text("Shutting down…")
          )
      end

    # The dimmed backdrop also cancels, like tapping outside a dialog.
    [
      Nearby.in_front(
        Input.button(
          [
            width(fill()),
            height(fill()),
            Background.color(color(:black, 400, 0.7)),
            Event.on_press(event(power, :cancel))
          ],
          # Taps on the card itself must not reach the backdrop; :request is
          # a no-op while the dialog is open.
          Input.button([center_x(), center_y(), Event.on_press(event(power, :request))], card)
        )
      )
    ]
  end

  defp loaded(nil, _view), do: NowPlaying.message("Loading…")
  defp loaded(state, view), do: view.(state)

  defp tab_bar(nil), do: none()

  defp tab_bar(nav) do
    row(
      [
        width(fill()),
        height(px(120)),
        padding(16),
        spacing(16),
        Background.color(color(:slate, 800))
      ],
      for {tab, label} <- @tabs do
        Components.button(
          [
            width(fill()),
            height(fill()),
            Font.size(28),
            Background.color(
              if selected?(tab, nav), do: color(:sky, 700), else: color(:slate, 700)
            )
          ],
          event(nav, :show, tab),
          text(label)
        )
      end
    )
  end

  # The queue belongs to the now playing tab.
  defp selected?(:now_playing, %{current: :queue}), do: true
  defp selected?(tab, nav), do: tab == nav.current

  @impl Solve.Lookup
  def handle_solve_updated(_updated, state), do: {:ok, Viewport.rerender(state)}
end
