defmodule SqueezeNexus7.MixProject do
  use Mix.Project

  @app :squeeze_nexus7
  @version "0.1.0"
  @all_targets [:nexus7]

  def project do
    [
      app: @app,
      version: @version,
      elixir: "~> 1.18",
      archives: [nerves_bootstrap: "~> 1.17"],
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.target(), Mix.env()),
      compilers: compilers(Mix.target()),
      make_clean: ["clean"],
      deps: deps(),
      # Tests cover pure modules; starting the app would search the network.
      aliases: [test: "test --no-start"],
      releases: [{@app, release()}]
    ]
  end

  def application do
    [
      extra_applications: [:logger, :runtime_tools, :inets],
      mod: {SqueezeNexus7.Application, []}
    ]
  end

  def cli do
    [preferred_targets: [run: :host, test: :host]]
  end

  defp deps do
    [
      {:nerves, "~> 1.13", runtime: false},
      {:shoehorn, "~> 0.9.1"},
      {:ring_logger, "~> 0.11.0"},
      {:toolshed, "~> 0.5.0"},
      {:nerves_runtime, "~> 0.13.12"},
      {:nerves_pack, "~> 0.7.1", targets: @all_targets},
      {:muontrap, "~> 1.5"},

      # UI: Emerge rendered headless, shown via KMS on the device (see lib_target/)
      {:emerge, path: "../emerge"},
      {:video_interop, path: "../video_interop", override: true},
      {:solve, "~> 0.3.1"},
      {:elixir_make, "~> 0.9", runtime: false},
      # Emerge builds its NIF from source for this target.
      {:rustler, "~> 0.38.0", runtime: false},
      {:nerves_system_nexus7,
       path: "../nerves_system_nexus7", runtime: false, targets: :nexus7, nerves: [compile: true]}
    ]
  end

  # The display, touch and audio glue (lib_target/) and its C helpers only
  # build for the device; lib_host/ has stand-ins for running on a PC.
  defp elixirc_paths(:host, :test), do: ["lib", "lib_host", "test/support"]
  defp elixirc_paths(:host, _env), do: ["lib", "lib_host"]
  defp elixirc_paths(_target, _env), do: ["lib", "lib_target"]

  defp compilers(:host), do: Mix.compilers()
  defp compilers(_target), do: [:elixir_make | Mix.compilers()]

  def release do
    [
      overwrite: true,
      cookie: "#{@app}_cookie",
      include_erts: &Nerves.Release.erts/0,
      steps: [&Nerves.Release.init/1, :assemble],
      strip_beams: Mix.env() == :prod or [keep: ["Docs"]]
    ]
  end
end
