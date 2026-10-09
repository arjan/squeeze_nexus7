defmodule SqueezeNexus7.State.Power do
  @moduledoc """
  The power button: pauses playback and asks before shutting down. The
  question goes away by itself after a while.
  """
  use Solve.Controller, events: [:request, :cancel, :confirm]

  alias SqueezeNexus7.Shutdown

  @timeout 15_000

  @impl true
  def init(_params, _dependencies), do: %{phase: :idle, timer: nil}

  @impl true
  def expose(state, _dependencies, _params), do: %{phase: state.phase}

  def request(_payload, %{phase: :idle} = state, _dependencies, callbacks) do
    callbacks.pause.()
    %{state | phase: :confirm, timer: Process.send_after(self(), :expire, @timeout)}
  end

  def request(_payload, state, _dependencies, _callbacks), do: state

  def cancel(_payload, %{phase: :confirm} = state), do: idle(state)
  def cancel(_payload, state), do: state

  def confirm(_payload, %{phase: :confirm} = state) do
    cancel_timer(state)
    # Let the "shutting down" notice render before the system goes away.
    Process.send_after(self(), :shutdown, 300)
    %{state | phase: :shutting_down, timer: nil}
  end

  def confirm(_payload, state), do: state

  def handle_info(:expire, %{phase: :confirm} = state), do: %{state | phase: :idle, timer: nil}

  def handle_info(:shutdown, state) do
    Shutdown.run()
    state
  end

  def handle_info(_other, state), do: state

  defp idle(state) do
    cancel_timer(state)
    %{state | phase: :idle, timer: nil}
  end

  defp cancel_timer(%{timer: nil}), do: :ok
  defp cancel_timer(%{timer: timer}), do: Process.cancel_timer(timer)
end
