defmodule SqueezeNexus7.Shutdown do
  @moduledoc "On a PC shutting down only logs."

  require Logger

  @spec run() :: :ok
  def run, do: Logger.info("shutdown requested")
end
