# squeeze_nexus7

A radio and music player for a Nexus 7 (2012) running Nerves, built with
[Emerge](https://github.com/emerge-elixir/emerge) and
[Solve](https://hex.pm/packages/solve). It plays through squeezelite, so the
tablet is a player in a Lyrion/Logitech Media Server (LMS) setup.

- **Radio**: favourite stations as tiles; browse the server's radio sources
  (TuneIn) and star stations to add or remove favourites.
- **Now Playing**: cover or station logo, progress, transport, volume, queue.
- **Library**: artists, albums and playlists.
- Volume buttons change the volume; the power button pauses and asks before
  shutting down.

The server is found automatically (UDP broadcast on port 3483).

## Building

Needs the sibling checkouts `../emerge`, `../video_interop` and
`../nerves_system_nexus7` (branch `squeezelite`), and Wi-Fi credentials in
`../.wifi-creds.txt`:

```
ssid: MyNetwork
pass: secret
```

The password ends up in plain text in the firmware image, so don't share
`.fw` files.

```sh
export MIX_TARGET=nexus7
mix deps.get
mix firmware
../upload.sh 172.31.191.165 _build/nexus7_dev/nerves/images/squeeze_nexus7.fw
```

On a PC, `mix run` renders the UI headless against a real server; set
`SQUEEZE_PLAYER` to an existing player's MAC and capture screens with
`SqueezeNexus7.Display.screenshot/1`.

The host and device builds share Emerge's native library in `../emerge/priv`.
After switching between them, run `mix deps.compile emerge --force` with the
matching `MIX_TARGET`.
