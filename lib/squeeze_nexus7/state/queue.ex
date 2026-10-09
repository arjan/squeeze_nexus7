defmodule SqueezeNexus7.State.Queue do
  @moduledoc """
  The player's queue (the LMS "current playlist"), one page at a time.
  Only runs while the queue screen is shown.
  """
  use Solve.Controller, events: [:page, :jump, :remove, :clear]

  alias SqueezeNexus7.{LocalPlayer, Lms}

  @page_size 8
  @refresh_delay 150

  @impl true
  def init(_params, _dependencies) do
    Lms.subscribe()
    fetch(%{id: LocalPlayer.id(), offset: 0, items: [], count: 0, current: nil, refresh: nil})
  end

  @impl true
  def expose(state, _dependencies, _params) do
    %{
      items: state.items,
      current: state.current,
      count: state.count,
      offset: state.offset,
      page_size: @page_size
    }
  end

  def page(direction, state) when direction in [-1, 1] do
    offset = state.offset + direction * @page_size

    if offset >= 0 and offset < state.count,
      do: fetch(%{state | offset: offset}),
      else: state
  end

  def jump(index, state) when is_integer(index) do
    Lms.command([state.id, "playlist", "index", index])
    %{state | current: index}
  end

  def remove(index, state) when is_integer(index) do
    Lms.command([state.id, "playlist", "delete", index])
    fetch(state)
  end

  def clear(_payload, state) do
    Lms.command([state.id, "playlist", "clear"])
    fetch(%{state | offset: 0})
  end

  def handle_info({:lms_event, [id, "playlist" | _]}, %{id: id, refresh: nil} = state),
    do: %{state | refresh: Process.send_after(self(), :refresh, @refresh_delay)}

  def handle_info(:refresh, state), do: fetch(%{state | refresh: nil})
  def handle_info(_other, state), do: state

  defp fetch(state) do
    case Lms.query([state.id, "status", state.offset, @page_size, "tags:ad"], "playlist index") do
      {:ok, {header, items, _count}} ->
        count = header |> Map.get("playlist_tracks", "0") |> String.to_integer()

        items =
          for item <- items do
            %{
              index: String.to_integer(item["playlist index"]),
              title: item["title"],
              artist: item["artist"],
              duration: item["duration"]
            }
          end

        current =
          case Integer.parse(header["playlist_cur_index"] || "") do
            {index, _} -> index
            :error -> nil
          end

        # Removing the last track of the last page leaves the page empty.
        if items == [] and state.offset > 0 and count > 0,
          do: fetch(%{state | offset: max(state.offset - @page_size, 0)}),
          else: %{state | items: items, count: count, current: current}

      {:error, _reason} ->
        state
    end
  end
end
