defmodule SqueezeNexus7.Input.Touch do
  @moduledoc """
  Reads the touchscreen through `priv/evtouch` and injects the touches into
  the panel's Emerge renderer as pointer events.

  `evtouch` prints `d x y`, `m x y` and `u x y` (down, move, up) in screen
  coordinates. Runs of queued moves are merged so a fast drag only injects the
  newest position; downs and ups keep their order.
  """
  use GenServer

  require Logger

  @device "/dev/input/event0"
  @viewport SqueezeNexus7.UI.Root

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    exe = Application.app_dir(:squeeze_nexus7, "priv/evtouch")

    port =
      Port.open({:spawn_executable, exe}, [
        {:args, [@device, "800", "1280"]},
        {:line, 64},
        :binary,
        :exit_status
      ])

    {:ok, %{port: port, renderer: nil}}
  end

  @impl true
  def handle_info({port, {:data, {:eol, line}}}, %{port: port} = state) do
    lines = [line | drain_lines(port)]

    state =
      lines
      |> Enum.map(&String.split/1)
      |> collapse_moves()
      |> Enum.reduce(state, &inject/2)

    {:noreply, state}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state),
    do: {:stop, {:evtouch_exit, status}, state}

  def handle_info(_other, state), do: {:noreply, state}

  defp drain_lines(port) do
    receive do
      {^port, {:data, {:eol, line}}} -> [line | drain_lines(port)]
    after
      0 -> []
    end
  end

  # Keeps only the last of consecutive moves.
  defp collapse_moves([["m" | _], ["m" | _] = next | rest]), do: collapse_moves([next | rest])
  defp collapse_moves([line | rest]), do: [line | collapse_moves(rest)]
  defp collapse_moves([]), do: []

  defp inject([kind, x, y], state) when kind in ["d", "m", "u"] do
    case renderer(state) do
      nil ->
        state

      renderer ->
        {x, y} = {String.to_integer(x), String.to_integer(y)}

        case kind do
          "d" ->
            EmergeSkia.inject_pointer(renderer, :move, x, y)
            EmergeSkia.inject_pointer(renderer, :press, x, y)

          "m" ->
            EmergeSkia.inject_pointer(renderer, :move, x, y)

          "u" ->
            EmergeSkia.inject_pointer(renderer, :release, x, y)
        end

        %{state | renderer: renderer}
    end
  rescue
    # The renderer restarted; look it up again on the next touch.
    error ->
      Logger.debug("touch injection failed: #{Exception.message(error)}")
      %{state | renderer: nil}
  end

  defp inject(_line, state), do: state

  defp renderer(%{renderer: renderer}) when not is_nil(renderer), do: renderer

  defp renderer(_state) do
    case Process.whereis(@viewport) do
      nil -> nil
      pid -> Emerge.Runtime.Viewport.renderer(pid)
    end
  end
end
