defmodule SqueezeNexus7.State.Library do
  @moduledoc """
  Browsing the music library: a section (artists, albums, playlists or
  favourites), drilled into level by level, one page at a time. Paging
  instead of scrolling keeps redraws small on the Tegra 3.

  Each item carries what it opens to and how it plays, so the UI only sends
  the item's position on the page.
  """
  use Solve.Controller, events: [:section, :open, :back, :page, :play, :add]

  alias SqueezeNexus7.{LocalPlayer, Lms}

  @page_size 8
  @sections [:artists, :albums, :playlists]

  @impl true
  def init(_params, _dependencies) do
    %{id: LocalPlayer.id(), section: :artists, levels: [], error: nil}
    |> push(root(:artists))
  end

  @impl true
  def expose(state, _dependencies, _params) do
    [level | _] = state.levels

    %{
      section: state.section,
      sections: @sections,
      title: level.title,
      depth: length(state.levels),
      items:
        Enum.map(
          level.items,
          &%{label: &1.label, detail: &1.detail, open?: &1.open != nil, play?: &1.play != nil}
        ),
      offset: level.offset,
      count: level.count,
      page_size: @page_size,
      error: state.error
    }
  end

  def section(section, state) when section in @sections,
    do: push(%{state | section: section, levels: []}, root(section))

  def section(_section, state), do: state

  def open(position, state) do
    case at(state, position) do
      %{open: level} when level != nil -> push(state, level)
      _ -> state
    end
  end

  def back(_payload, %{levels: [_, _ | _] = levels} = state), do: %{state | levels: tl(levels)}
  def back(_payload, state), do: state

  def page(direction, %{levels: [level | rest]} = state) when direction in [-1, 1] do
    offset = level.offset + direction * @page_size

    if offset >= 0 and offset < level.count,
      do: load(state, %{level | offset: offset}, rest),
      else: state
  end

  def play(position, state, _dependencies, callbacks),
    do: control(state, position, "load", callbacks)

  def add(position, state, _dependencies, callbacks),
    do: control(state, position, "add", callbacks)

  defp control(state, position, cmd, callbacks) do
    case at(state, position) do
      %{play: {key, id}} ->
        Lms.command([state.id, "playlistcontrol", "cmd:#{cmd}", "#{key}:#{id}"])
        played(callbacks, cmd)

      _ ->
        :ok
    end

    state
  end

  # Starting playback switches to the now playing screen; adding stays here.
  defp played(%{played: played}, "load"), do: played.()
  defp played(_callbacks, _cmd), do: :ok

  defp at(%{levels: [level | _]}, position) when is_integer(position),
    do: Enum.at(level.items, position)

  defp at(_state, _position), do: nil

  defp push(state, level), do: load(state, level, state.levels)

  defp load(state, level, rest) do
    case Lms.query(query(level), "id") do
      {:ok, {_header, items, count}} ->
        level = %{level | items: Enum.map(items, &to_item(level.kind, &1)), count: count || 0}
        %{state | levels: [level | rest], error: nil}

      {:error, reason} ->
        level = %{level | items: [], count: 0}
        %{state | levels: [level | rest], error: "Could not load: #{inspect(reason)}"}
    end
  end

  defp root(:artists), do: level(:artists, "Artists")
  defp root(:albums), do: level(:albums, "Albums")
  defp root(:playlists), do: level(:playlists, "Playlists")

  defp level(kind, title, filters \\ []),
    do: %{kind: kind, title: title, filters: filters, offset: 0, items: [], count: 0}

  defp query(%{kind: kind, offset: offset, filters: filters}) do
    case kind do
      :artists -> ["artists", offset, @page_size]
      :albums -> ["albums", offset, @page_size, "tags:la", "sort:album" | filters]
      :tracks -> ["titles", offset, @page_size, "tags:atd", "sort:tracknum" | filters]
      :playlists -> ["playlists", offset, @page_size]
    end
  end

  defp to_item(:artists, %{"id" => id, "artist" => name}) do
    %{
      label: name,
      detail: nil,
      open: level(:albums, name, ["artist_id:#{id}"]),
      play: {"artist_id", id}
    }
  end

  defp to_item(:albums, %{"id" => id} = album) do
    %{
      label: album["album"],
      detail: album["artist"],
      open: level(:tracks, album["album"], ["album_id:#{id}"]),
      play: {"album_id", id}
    }
  end

  defp to_item(:tracks, %{"id" => id} = track) do
    %{label: track["title"], detail: track["artist"], open: nil, play: {"track_id", id}}
  end

  defp to_item(:playlists, %{"id" => id} = playlist) do
    %{label: playlist["playlist"], detail: nil, open: nil, play: {"playlist_id", id}}
  end

  defp to_item(_kind, other),
    do: %{label: other["name"] || "?", detail: nil, open: nil, play: nil}
end
