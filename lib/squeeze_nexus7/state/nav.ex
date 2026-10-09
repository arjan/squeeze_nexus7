defmodule SqueezeNexus7.State.Nav do
  @moduledoc "Which screen is shown."
  use Solve.Controller, events: [:show]

  @screens [:radio, :now_playing, :library, :queue]

  # Radio is what the tablet is mostly used for.
  @impl true
  def init(_params, _dependencies), do: %{current: :radio}

  def show(screen, state) when screen in @screens, do: %{state | current: screen}
  def show(_screen, state), do: state
end
