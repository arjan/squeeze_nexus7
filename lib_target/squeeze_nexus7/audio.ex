defmodule SqueezeNexus7.Audio do
  @moduledoc """
  Switches on the RT5640 speaker route, which is off at boot (see the
  nerves_system_nexus7 README). LMS controls the volume in software, so the
  hardware speaker level stays fixed.
  """

  require Logger

  @controls [
    "DAC MIXL INF1",
    "DAC MIXR INF1",
    "Stereo DAC MIXL DAC L1",
    "Stereo DAC MIXR DAC R1",
    "SPK MIXL DAC L1",
    "SPK MIXR DAC R1",
    "SPOL MIX SPKVOL L",
    "SPOR MIX SPKVOL R",
    "Speaker Channel",
    "Speaker L",
    "Speaker R",
    "Int Spk",
    "Speakers"
  ]

  # 0-39; 31 is 0 dB.
  @speaker_level "31"

  @spec enable_speaker() :: :ok
  def enable_speaker do
    for control <- @controls, do: amixer(["sset", control, "on"])
    amixer(["sset", "Speaker", @speaker_level])
    :ok
  end

  defp amixer(args) do
    case System.cmd("amixer", ["-q", "-c", "0" | args], stderr_to_stdout: true) do
      {_, 0} -> :ok
      {output, _} -> Logger.warning("amixer #{Enum.join(args, " ")}: #{String.trim(output)}")
    end
  end
end
