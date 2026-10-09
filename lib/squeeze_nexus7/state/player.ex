defmodule SqueezeNexus7.State.Player do
  @moduledoc """
  Now playing on this tablet's player: track, progress, volume and cover,
  plus the transport controls.

  The status is fetched again shortly after LMS reports a change for this
  player. While playing, the elapsed time advances locally every second.
  Seek and volume come from sliders that report every drag step, so only the
  last value within `@settle` ms is sent to the server.
  """
  use Solve.Controller,
    events: [:toggle, :pause, :next, :previous, :seek, :volume, :volume_step]

  alias SqueezeNexus7.{Art, LocalPlayer, Lms}

  @refresh_delay 100
  @settle 250
  @tags "tags:alcdKN"

  @impl true
  def init(_params, _dependencies) do
    Lms.subscribe()
    Process.send_after(self(), :tick, 1_000)

    fetch(%{
      id: LocalPlayer.id(),
      known?: false,
      mode: "stop",
      remote?: false,
      track: %{},
      title: nil,
      time: 0.0,
      synced_at: now(),
      clock: now(),
      duration: 0.0,
      volume: 50,
      art_key: nil,
      art: nil,
      refresh: nil,
      pending: %{}
    })
  end

  @impl true
  def expose(state, _dependencies, _params) do
    track = state.track

    %{
      known?: state.known?,
      playing?: state.mode == "play",
      remote?: state.remote?,
      has_track?: track != %{},
      title: track["title"] || state.title,
      artist: track["artist"],
      album: track["album"],
      remote_title: track["remote_title"],
      duration: state.duration,
      elapsed: min(elapsed(state), max(state.duration, 0.0)),
      volume: Map.get(state.pending, :volume, state.volume),
      art: state.art
    }
  end

  def toggle(_payload, %{mode: "play"} = state), do: command(state, ["pause", "1"], mode: "pause")
  def toggle(_payload, state), do: command(state, ["play"], mode: "play")

  def pause(_payload, %{mode: "play"} = state), do: command(state, ["pause", "1"], mode: "pause")
  def pause(_payload, state), do: state

  def next(_payload, state), do: command(state, ["playlist", "index", "+1"], [])
  def previous(_payload, state), do: command(state, ["playlist", "index", "-1"], [])

  def seek(seconds, state) when is_number(seconds) do
    t = now()
    settle(%{state | time: seconds * 1.0, synced_at: t, clock: t}, :seek, seconds)
  end

  def volume(level, state) when is_number(level), do: settle(state, :volume, round(level))

  # Hardware volume buttons; steps add up while a button is held.
  def volume_step(delta, state) when is_integer(delta) do
    level = Map.get(state.pending, :volume, state.volume) + delta
    settle(state, :volume, level |> max(0) |> min(100))
  end

  def handle_info({:lms_event, [id | _]}, %{id: id} = state), do: schedule_refresh(state)
  def handle_info({:lms_server, _server}, state), do: state
  def handle_info(:refresh, state), do: fetch(%{state | refresh: nil})

  def handle_info(:tick, state) do
    Process.send_after(self(), :tick, 1_000)
    if state.mode == "play", do: %{state | clock: now()}, else: state
  end

  def handle_info({:settled, key}, state) do
    case Map.pop(state.pending, key) do
      {nil, _} -> state
      {value, pending} -> send_setting(%{state | pending: pending}, key, value)
    end
  end

  def handle_info({:art_ready, key, path}, %{art_key: key} = state), do: %{state | art: path}
  def handle_info(_other, state), do: state

  defp settle(state, key, value) do
    unless Map.has_key?(state.pending, key),
      do: Process.send_after(self(), {:settled, key}, @settle)

    %{state | pending: Map.put(state.pending, key, value)}
  end

  defp send_setting(state, :seek, seconds) do
    Lms.command([state.id, "time", Float.round(seconds * 1.0, 1)])
    state
  end

  defp send_setting(state, :volume, level) do
    Lms.command([state.id, "mixer", "volume", level])
    %{state | volume: level}
  end

  # Applies the expected result right away so the button reacts before the
  # server's notification arrives.
  defp command(state, args, changes) do
    Lms.command([state.id | args])
    t = now()
    state = %{state | time: elapsed(%{state | clock: t}), synced_at: t, clock: t}
    Enum.reduce(changes, state, fn {key, value}, acc -> Map.put(acc, key, value) end)
  end

  defp schedule_refresh(%{refresh: nil} = state),
    do: %{state | refresh: Process.send_after(self(), :refresh, @refresh_delay)}

  defp schedule_refresh(state), do: state

  defp fetch(state) do
    case Lms.query([state.id, "status", "-", "1", @tags], "playlist index") do
      {:ok, {%{"mode" => mode} = header, items, _count}} ->
        track = List.first(items, %{})

        %{
          state
          | known?: true,
            mode: mode,
            remote?: header["remote"] == "1",
            track: track,
            title: header["current_title"],
            time: number(header["time"]),
            synced_at: now(),
            clock: now(),
            duration: number(track["duration"] || header["duration"]),
            volume: header |> Map.get("mixer volume", "50") |> number() |> round() |> abs()
        }
        |> load_art(track)

      # Unknown player: squeezelite hasn't connected yet. LMS announces it
      # with a "client new" notification.
      {:ok, _reply} ->
        %{state | known?: false}

      {:error, _reason} ->
        state
    end
  end

  defp load_art(state, track) do
    case Art.source(track) do
      nil ->
        %{state | art_key: nil, art: nil}

      {key, _path} when key == state.art_key ->
        state

      {key, _path} = source ->
        case Art.cached(key) do
          nil ->
            Art.fetch(source)
            %{state | art_key: key, art: nil}

          path ->
            %{state | art_key: key, art: path}
        end
    end
  end

  # `clock` advances on every tick, so the exposed time follows it.
  defp elapsed(%{mode: "play"} = state), do: state.time + (state.clock - state.synced_at) / 1000
  defp elapsed(state), do: state.time

  defp now, do: System.monotonic_time(:millisecond)

  defp number(nil), do: 0.0

  defp number(value) do
    case Float.parse(value) do
      {number, _} -> number
      :error -> 0.0
    end
  end
end
