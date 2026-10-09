defmodule SqueezeNexus7.BootLog do
  @moduledoc """
  Debug aid: periodically saves the kernel log and the Elixir log to the
  application partition so they survive a reset.

  Files are written to `/root/boot-logs/` and can be read on a host by
  mounting the tablet's eMMC via U-Boot's "mount internal storage".
  """
  use Task, restart: :permanent

  require Logger

  @dir "/root/boot-logs"
  @interval 5_000

  def start_link(_args), do: Task.start_link(&init/0)

  defp init() do
    File.mkdir_p!(@dir)
    boot = next_boot_number()
    Logger.info("BootLog: writing logs for boot #{boot} to #{@dir}")
    loop(boot, System.monotonic_time(:second))
  end

  defp loop(boot, t0) do
    uptime = System.monotonic_time(:second) - t0
    {dmesg, _} = System.cmd("dmesg", [], stderr_to_stdout: true)
    File.write!(Path.join(@dir, "boot#{boot}-dmesg.txt"), dmesg)
    _ = RingLogger.save(Path.join(@dir, "boot#{boot}-elixir.txt"))
    # Nerves' busybox has no `sync` command; the :sync mode flushes this file.
    File.write!(Path.join(@dir, "boot#{boot}-alive.txt"), "uptime #{uptime}s\n", [:sync])
    Process.sleep(@interval)
    loop(boot, t0)
  end

  defp next_boot_number() do
    counter = Path.join(@dir, "boot-count")

    n =
      case File.read(counter) do
        {:ok, s} -> String.to_integer(String.trim(s)) + 1
        _ -> 1
      end

    File.write!(counter, "#{n}\n")
    n
  end
end
