defmodule SqueezeNexus7.Display.FrameSink do
  @moduledoc """
  Receives partial headless frames from Emerge and shows them on the panel.

  Emerge sends `{:emerge_skia_frame, frame, {x, y}}` where `frame` holds only
  the changed rectangle. Every frame already queued is staged before a single
  flip: a flip waits for vsync, so flipping per frame would let fast input
  build a backlog.
  """
  use GenServer

  alias SqueezeNexus7.Display.Drm

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    {:ok, display, _info} = Drm.open(~c"/dev/dri/card0")
    {:ok, display}
  end

  @impl true
  def handle_info({:emerge_skia_frame, _frame, _position} = message, display) do
    stage_queued(display, message)
    {_copy_us, _flip_us, _rows} = Drm.commit(display)
    {:noreply, display}
  end

  def handle_info(_other, display), do: {:noreply, display}

  @impl true
  def terminate(_reason, display), do: Drm.close(display)

  defp stage_queued(display, {:emerge_skia_frame, frame, {x, y}}) do
    %VideoInterop.Frame{coded_width: w, coded_height: h, storage: %{data: data}} = frame
    :ok = Drm.stage_region(display, data, x, y, w, h)

    receive do
      {:emerge_skia_frame, _frame, _position} = next -> stage_queued(display, next)
    after
      0 -> :ok
    end
  end
end
