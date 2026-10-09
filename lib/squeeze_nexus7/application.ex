defmodule SqueezeNexus7.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children =
      boot_log() ++
        [
          {Task, &SqueezeNexus7.Audio.enable_speaker/0},
          {Registry, keys: :duplicate, name: SqueezeNexus7.Lms.Registry},
          SqueezeNexus7.Lms,
          SqueezeNexus7.LocalPlayer,
          SqueezeNexus7.Art,
          {SqueezeNexus7.State, name: SqueezeNexus7.State},
          buttons(),
          %{
            id: :display,
            start:
              {Supervisor, :start_link,
               [SqueezeNexus7.Display.children(), [strategy: :rest_for_one]]},
            type: :supervisor
          }
        ]

    children = List.flatten(children)
    Supervisor.start_link(children, strategy: :one_for_one, name: SqueezeNexus7.Supervisor)
  end

  if Mix.target() == :host do
    defp boot_log, do: []
    defp buttons, do: []
  else
    defp boot_log, do: [SqueezeNexus7.BootLog]
    defp buttons, do: [SqueezeNexus7.Input.Buttons]
  end
end
