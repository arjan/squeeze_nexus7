defmodule SqueezeNexus7.State do
  @moduledoc """
  The app's state graph.

  `:player`, `:radio`, `:library` and `:queue` run only while the music server is
  connected, keyed on the connection generation so they start fresh after a
  reconnect. `:queue` also only runs while its screen is shown.
  """
  use Solve

  alias SqueezeNexus7.State

  @impl Solve
  def controllers do
    [
      controller!(name: :device, module: State.Device),
      controller!(name: :server, module: State.Server),
      controller!(name: :nav, module: State.Nav),
      controller!(
        name: :power,
        module: State.Power,
        callbacks: %{pause: fn -> dispatch(:player, :pause) end}
      ),
      controller!(
        name: :player,
        module: State.Player,
        dependencies: [:server],
        params: &connected/1
      ),
      controller!(
        name: :radio,
        module: State.Radio,
        dependencies: [:server, :player],
        params: &connected/1
      ),
      controller!(
        name: :library,
        module: State.Library,
        dependencies: [:server],
        params: &connected/1,
        callbacks: %{played: fn -> dispatch(:nav, :show, :now_playing) end}
      ),
      controller!(
        name: :queue,
        module: State.Queue,
        dependencies: [:server, :nav],
        params: fn %{dependencies: %{nav: nav}} = input ->
          nav && nav.current == :queue && connected(input)
        end
      )
    ]
  end

  defp connected(%{dependencies: %{server: %{phase: :connected, generation: generation}}}),
    do: %{generation: generation}

  defp connected(_input), do: false
end
