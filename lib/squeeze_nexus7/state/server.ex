defmodule SqueezeNexus7.State.Server do
  @moduledoc """
  The music server connection: searching, connecting or connected, and the
  server's name. `generation` changes on every new connection, so
  controllers keyed on it start fresh after a reconnect.
  """
  use Solve.Controller, events: []

  alias SqueezeNexus7.Lms

  @impl true
  def init(_params, _dependencies), do: Lms.subscribe()

  @impl true
  def expose(server, _dependencies, _params) do
    Map.take(server, [:phase, :name, :generation])
  end

  def handle_info({:lms_server, server}, _state), do: server
  def handle_info(_other, state), do: state
end
