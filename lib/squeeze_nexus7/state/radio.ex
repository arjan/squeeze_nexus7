defmodule SqueezeNexus7.State.Radio do
  @moduledoc """
  Radio, in two sections:

    * Favourites: the LMS favourites as a page of tiles with logos. A tap
      plays the station right away, so zapping stays on this screen; the
      station that is playing is marked. In edit mode a tap removes it.
    * Browse: the radio sources LMS offers (TuneIn's local radio, music,
      news, ...), drilled into level by level. Stations play with a tap and
      can be starred to add or remove them as favourites.

  Item ids change when LMS rebuilds a menu, so they are only used for the
  page that was just loaded. Favourites are matched to browsed stations by
  their TuneIn station id, since the two carry different stream URLs.
  """
  use Solve.Controller,
    events: [:section, :play, :open, :back, :page, :edit, :star]

  alias SqueezeNexus7.{Art, LocalPlayer, Lms, Lms.Protocol}

  @sections [:favorites, :browse]
  @page_sizes %{favorites: 6, browse: 7}
  @max_favorites 500
  @reload_delay 700

  @impl true
  def init(_params, _dependencies) do
    %{
      id: LocalPlayer.id(),
      section: :favorites,
      editing?: false,
      levels: %{favorites: [], browse: []},
      starred: %{},
      logos: %{},
      error: nil
    }
    |> load_starred()
    |> push(:favorites, level(:favorites, "Favourites"))
    |> push(:browse, level(:sources, "Browse"))
  end

  @impl true
  def expose(state, dependencies, _params) do
    [level | _] = state.levels[state.section]
    player = dependencies[:player]

    %{
      section: state.section,
      sections: @sections,
      editing?: state.editing?,
      title: level.title,
      depth: length(state.levels[state.section]),
      offset: level.offset,
      count: level.count,
      page_size: @page_sizes[state.section],
      error: state.error,
      items:
        for item <- level.items do
          %{
            name: item.name,
            folder?: item.folder?,
            playable?: item.play != nil,
            starred?: Map.has_key?(state.starred, item.key),
            logo: item.logo && state.logos[elem(item.logo, 0)],
            playing?: playing?(item, player)
          }
        end
    }
  end

  # LMS reports the station's name as the stream's remote title.
  defp playing?(%{play: play, name: name}, %{playing?: true, remote?: true} = player)
       when play != nil,
       do: name in [player.remote_title, player.album]

  defp playing?(_item, _player), do: false

  def section(section, state) when section in @sections,
    do: %{state | section: section, editing?: false}

  def section(_section, state), do: state

  def edit(_payload, %{section: :favorites} = state), do: %{state | editing?: not state.editing?}
  def edit(_payload, state), do: state

  def play(position, %{section: :favorites, editing?: true} = state) do
    case at(state, position) do
      %{fav_id: fav_id} when fav_id != nil -> remove_favorite(state, fav_id)
      _ -> state
    end
  end

  def play(position, state) do
    case at(state, position) do
      %{play: tokens} when tokens != nil -> Lms.command([state.id | tokens])
      _ -> :ok
    end

    state
  end

  def open(position, state) do
    case at(state, position) do
      %{open: level} when level != nil -> push(state, state.section, level)
      _ -> state
    end
  end

  def back(_payload, state) do
    case state.levels[state.section] do
      [_, _ | _] = levels -> put_in(state, [:levels, state.section], tl(levels))
      _ -> state
    end
  end

  def page(direction, state) when direction in [-1, 1] do
    [level | rest] = state.levels[state.section]
    offset = level.offset + direction * @page_sizes[state.section]

    if offset >= 0 and offset < level.count,
      do: load(state, state.section, %{level | offset: offset}, rest),
      else: state
  end

  # Adds a browsed station to the favourites, or removes it if it is one.
  def star(position, state) do
    case at(state, position) do
      %{key: key, url: url} = item when url != nil ->
        case state.starred[key] do
          nil ->
            Lms.command(["favorites", "add", "url:#{url}", "title:#{item.name}" | icon(item)])
            refresh_favorites(put_in(state, [:starred, key], :pending))

          :pending ->
            state

          fav_id ->
            remove_favorite(state, fav_id)
        end

      _ ->
        state
    end
  end

  def handle_info({:art_ready, key, path}, state), do: put_in(state, [:logos, key], path)

  def handle_info(:reload_favorites, state) do
    [level | rest] = state.levels.favorites
    state |> load_starred() |> load(:favorites, level, rest)
  end

  def handle_info(_other, state), do: state

  defp icon(%{image: image}) when is_binary(image), do: ["icon:#{image}"]
  defp icon(_item), do: []

  defp remove_favorite(state, fav_id) do
    Lms.command(["favorites", "delete", "item_id:#{index_id(fav_id)}"])
    starred = Map.reject(state.starred, fn {_key, id} -> id == fav_id end)
    refresh_favorites(%{state | starred: starred})
  end

  # Menu ids carry a session prefix ("697630d9.5"); playing accepts them but
  # deleting needs the plain index ("5", or "2.1" inside a folder).
  defp index_id(fav_id), do: String.replace(fav_id, ~r/\A[0-9a-f]+\./, "")

  # Favourite ids shift after a change, so the list and the stars reload.
  # LMS applies the change shortly after replying, hence the delay; until
  # then the stars show the expected result.
  defp refresh_favorites(state) do
    Process.send_after(self(), :reload_favorites, @reload_delay)
    state
  end

  defp at(state, position) when is_integer(position) do
    [level | _] = state.levels[state.section]
    Enum.at(level.items, position)
  end

  defp at(_state, _position), do: nil

  defp level(kind, title, source \\ nil, filters \\ []),
    do: %{
      kind: kind,
      title: title,
      source: source,
      filters: filters,
      offset: 0,
      items: [],
      count: 0
    }

  defp push(state, section, level), do: load(state, section, level, state.levels[section])

  defp load(state, section, level, rest) do
    case fetch(state, level, @page_sizes[section]) do
      {:ok, items, count} ->
        state = Enum.reduce(items, state, &load_logo/2)
        level = %{level | items: items, count: count || 0}
        %{put_in(state, [:levels, section], [level | rest]) | error: nil}

      {:error, reason} ->
        state = put_in(state, [:levels, section], [level | rest])
        %{state | error: "Could not load stations: #{inspect(reason)}"}
    end
  end

  defp fetch(_state, %{kind: :sources, offset: offset}, size) do
    with {:ok, reply} <- Lms.request(["radios", offset, size]) do
      {sources, count} = reply |> Protocol.pairs() |> Protocol.items_by_repeat(["sort"])

      # Search sources need text input, which the tablet doesn't have.
      items =
        for %{"cmd" => cmd, "name" => name, "type" => "xmlbrowser"} = source <- sources do
          %{
            name: name,
            folder?: true,
            open: level(:items, name, cmd),
            play: nil,
            key: nil,
            url: nil,
            fav_id: nil,
            image: nil,
            logo: Art.logo_source(source["icon"])
          }
        end

      {:ok, items, count}
    end
  end

  defp fetch(_state, %{kind: :favorites} = level, size) do
    query = ["favorites", "items", level.offset, size, "want_url:1" | level.filters]

    with {:ok, {_header, items, count}} <- Lms.query(query, "id") do
      {:ok, Enum.flat_map(items, &favorite/1), count}
    end
  end

  defp fetch(state, %{kind: :items, source: source} = level, size) do
    query = [state.id, source, "items", level.offset, size, "want_url:1" | level.filters]

    with {:ok, {_header, items, count}} <- Lms.query(query, "id") do
      {:ok, Enum.flat_map(items, &browsed(source, &1)), count}
    end
  end

  defp favorite(%{"id" => id, "name" => name} = item) do
    [
      %{
        name: name,
        folder?: item["hasitems"] == "1",
        open: if(item["hasitems"] == "1", do: level(:favorites, name, nil, ["item_id:#{id}"])),
        play: if(item["isaudio"] == "1", do: ["favorites", "playlist", "play", "item_id:#{id}"]),
        key: station_key(item["url"]),
        url: item["url"],
        fav_id: id,
        image: item["image"],
        logo: Art.logo_source(item["image"])
      }
    ]
  end

  defp favorite(_item), do: []

  defp browsed(source, %{"id" => id, "name" => name} = item) do
    [
      %{
        name: name,
        folder?: item["hasitems"] == "1",
        open: if(item["hasitems"] == "1", do: level(:items, name, source, ["item_id:#{id}"])),
        play: if(item["isaudio"] == "1", do: [source, "playlist", "play", "item_id:#{id}"]),
        key: station_key(item["url"]),
        url: if(item["isaudio"] == "1", do: item["url"]),
        fav_id: nil,
        image: item["image"],
        logo: Art.logo_source(item["image"])
      }
    ]
  end

  defp browsed(_source, _item), do: []

  # Top-level favourites by station, for the stars in Browse.
  defp load_starred(state) do
    case Lms.query(["favorites", "items", 0, @max_favorites, "want_url:1"], "id") do
      {:ok, {_header, items, _count}} ->
        starred =
          for %{"id" => id, "url" => url} <- items, into: %{}, do: {station_key(url), id}

        %{state | starred: starred}

      {:error, _reason} ->
        state
    end
  end

  # TuneIn stream URLs differ per menu (a serial parameter); the station id
  # (id=s9483) identifies the station.
  defp station_key(nil), do: nil

  defp station_key(url) do
    case Regex.run(~r/[?&]id=(s\d+)/, url) do
      [_, station] -> "tunein:" <> station
      nil -> url
    end
  end

  defp load_logo(%{logo: nil}, state), do: state

  defp load_logo(%{logo: {key, _path} = source}, state) do
    case state.logos[key] || Art.cached(key) do
      nil ->
        Art.fetch(source)
        state

      path ->
        put_in(state, [:logos, key], path)
    end
  end
end
