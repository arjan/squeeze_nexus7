defmodule SqueezeNexus7.LocalPlayer do
  @moduledoc """
  Runs squeezelite, which plays the audio LMS streams to this tablet, and
  knows its player id.

  squeezelite is started once the server is found and pointed at it, so it
  joins the same server the UI talks to. The player id is a MAC address
  derived from the device serial number, stable across reboots, so LMS keeps
  the player's queue and settings.

  On a PC (`squeezelite: false`) nothing is started and `id/0` returns the
  configured `:player_id` of an existing player.
  """
  use GenServer

  require Logger

  alias SqueezeNexus7.Lms

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @doc "The LMS player id (MAC address) the UI controls."
  @spec id() :: String.t() | nil
  def id do
    case Application.get_env(:squeeze_nexus7, :player_id) do
      nil -> mac_from_serial()
      id -> String.downcase(id)
    end
  end

  # Locally administered unicast MAC (02:...), so it can't clash with hardware.
  defp mac_from_serial do
    <<a, b, c, d, e, _::binary>> = :crypto.hash(:sha256, Nerves.Runtime.serial_number())

    [2, a, b, c, d, e]
    |> Enum.map_join(":", &(&1 |> Integer.to_string(16) |> String.pad_leading(2, "0")))
    |> String.downcase()
  end

  @impl true
  def init(nil) do
    case Application.get_env(:squeeze_nexus7, :squeezelite) do
      false ->
        :ignore

      config ->
        server = Lms.subscribe()
        {:ok, maybe_start(%{config: config, ip: nil, daemon: nil}, server)}
    end
  end

  @impl true
  def handle_info({:lms_server, server}, state), do: {:noreply, maybe_start(state, server)}
  def handle_info(_other, state), do: {:noreply, state}

  defp maybe_start(%{ip: ip} = state, %{phase: :connected, ip: ip}), do: state

  defp maybe_start(state, %{phase: :connected, ip: ip, name: name}) do
    if state.daemon, do: GenServer.stop(state.daemon)

    args = [
      "-s",
      ip |> :inet.ntoa() |> to_string(),
      "-o",
      state.config[:output],
      "-m",
      id(),
      "-n",
      "Nexus 7",
      "-C",
      "5"
    ]

    Logger.info("squeezelite: joining #{name}")

    {:ok, daemon} =
      MuonTrap.Daemon.start_link(state.config[:path], args,
        log_output: :info,
        log_prefix: "squeezelite: "
      )

    %{state | ip: ip, daemon: daemon}
  end

  defp maybe_start(state, _server), do: state
end
