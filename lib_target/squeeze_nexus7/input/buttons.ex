defmodule SqueezeNexus7.Input.Buttons do
  @moduledoc """
  Reads the volume and power buttons (the `gpio-keys` input device) and turns
  them into app events: volume steps, and a shutdown request for power.

  Events are read as raw `struct input_event` records (16 bytes on this 32-bit
  kernel) through `cat`, so no NIF or extra helper is needed.
  """
  use GenServer

  require Logger

  alias SqueezeNexus7.State

  @ev_key 1
  @key_volume_down 114
  @key_volume_up 115
  @key_power 116
  @volume_step 5

  def start_link(_opts), do: GenServer.start_link(__MODULE__, nil, name: __MODULE__)

  @impl true
  def init(nil) do
    case device() do
      nil ->
        Logger.warning("buttons: no gpio-keys input device")
        :ignore

      path ->
        port = Port.open({:spawn_executable, "/bin/cat"}, [:binary, :exit_status, args: [path]])
        {:ok, %{port: port, buffer: <<>>}}
    end
  end

  @impl true
  def handle_info({port, {:data, data}}, %{port: port} = state) do
    {:noreply, %{state | buffer: events(state.buffer <> data)}}
  end

  def handle_info({port, {:exit_status, status}}, %{port: port} = state),
    do: {:stop, {:cat_exit, status}, state}

  def handle_info(_other, state), do: {:noreply, state}

  defp events(
         <<_sec::32, _usec::32, type::little-16, code::little-16, value::little-signed-32,
           rest::binary>>
       ) do
    if type == @ev_key, do: key(code, value)
    events(rest)
  end

  defp events(partial), do: partial

  # value: 1 press, 2 auto-repeat while held, 0 release.
  defp key(@key_volume_up, value) when value in [1, 2],
    do: Solve.dispatch(State, :player, :volume_step, @volume_step)

  defp key(@key_volume_down, value) when value in [1, 2],
    do: Solve.dispatch(State, :player, :volume_step, -@volume_step)

  defp key(@key_power, 1), do: Solve.dispatch(State, :power, :request, %{})
  defp key(_code, _value), do: :ok

  # Finds the event node of the input device named "gpio-keys".
  defp device do
    "/proc/bus/input/devices"
    |> File.read!()
    |> String.split("\n\n", trim: true)
    |> Enum.find_value(fn block ->
      if block =~ ~s(Name="gpio-keys"),
        do:
          with(
            [_, event] <- Regex.run(~r/Handlers=.*?(event\d+)/, block),
            do: "/dev/input/" <> event
          )
    end)
  end
end
