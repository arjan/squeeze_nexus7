defmodule SqueezeNexus7.Display do
  @moduledoc """
  On a PC frames are rendered but dropped; capture them with
  `SqueezeNexus7.Display.screenshot/1`.
  """
  use GenServer

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil), do: {:ok, nil}

  @impl true
  def handle_info(_frame, state), do: {:noreply, state}

  def headless_opts, do: [target: Process.whereis(__MODULE__), pixel_format: :rgba8888]

  def children, do: [__MODULE__, {SqueezeNexus7.UI.Root, name: SqueezeNexus7.UI.Root}]

  @doc "Writes the current screen to a PNG file."
  def screenshot(path) do
    renderer = Emerge.Runtime.Viewport.renderer(Process.whereis(SqueezeNexus7.UI.Root))
    {:ok, png} = EmergeSkia.render_to_png(renderer)
    File.write!(path, png)
  end
end
