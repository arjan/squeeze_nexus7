defmodule SqueezeNexus7.Shutdown do
  @moduledoc "Powers the tablet off cleanly."

  @spec run() :: :ok
  def run, do: Nerves.Runtime.poweroff()
end
