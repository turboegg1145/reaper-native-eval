# Headless REAPER native ReaScript evaluation sandbox

A Docker-only evaluation harness for **raw, native REAPER Lua (ReaScript)**.
The model writes an ordinary synchronous `.lua` script; the container executes
it under a virtual X server, then saves the project and renders audio. There is
no Python harness, no Lua wrapper library, no Wine, and no plugin bridge.

## Requirements

- Linux x86_64 host with Docker (tested with Docker 29.1.3).
- Network access during `docker build` (official REAPER and upstream plugins).
- About 3 GB of free disk space for the image and build cache.

## Quick start

Use the public prebuilt image (recommended), or build locally.

```bash
# 1a. Pull the public x86_64 image.
docker pull ghcr.io/turboegg1145/reaper-native-eval:7.85

# 2a. Run the full-chain smoke test against the pulled image.
REAPER_IMAGE=ghcr.io/turboegg1145/reaper-native-eval:7.85 ./run_test.sh
```

Or build from source (the build also warms REAPER's VST3/CLAP scan cache):

```bash
./build.sh
./run_test.sh
```

The GHCR package (`ghcr.io/turboegg1145/reaper-native-eval`) is public;
anonymous pulls are verified with an empty Docker config. The image includes REAPER,
Surge XT, and Dragonfly Reverb. REAPER itself remains proprietary; this image is
intended for evaluation and testing, subject to the upstream licenses.

Expected artifacts:

```text
workspace/output.rpp   REAPER project, 48 kHz, rendered range = entire project
workspace/output.wav   stereo 48 kHz WAV, master mix
```

`run_test.sh` exits non-zero if either artifact is missing. The smoke test
normally completes in about 3 seconds and produces an audible 8-second file
(four chords, four beats each at 120 BPM).

## Evaluate a model

```bash
./run.sh /absolute/path/to/agent_song.lua
```

`run.sh` copies the script to `workspace/agent_song.lua`, starts the container,
and validates that `output.wav` and `output.rpp` exist. Set `REAPER_IMAGE` to
run a pulled image without retagging it; the default is `reaper-native-eval:7.85`. On a Lua failure it
prints the error and exits 1; the full error is also in `workspace/error.log`.
A hard wall-clock limit (default 300 s) kills a script stuck in a modal API or
an infinite loop; override it with `REAPER_TIMEOUT_SECS=...`.

The script contract is deliberately minimal:

- Write plain native `reaper.*` ReaScript, synchronously.
- Do not call Python, external Lua modules, or GUI dialogs/message boxes.
- Do not quit REAPER or render manually; `runner_wrapper.lua` owns save/render.
- The output project is whatever project is current when the script returns.

## Layout

| Path | Purpose |
| --- | --- |
| `Dockerfile` | Ubuntu 24.04, Xvfb, ffmpeg, REAPER, Surge XT, Dragonfly Reverb, build-time cache warm-up |
| `reaper.ini` | Dummy audio backend and no-dialog startup/render settings |
| `bootstrap_scan.lua` | Build-time plugin scan warm-up; quits with action 40004 |
| `runner_wrapper.lua` | `pcall(dofile(...))`, deterministic render settings, RPP/WAV validation, clean quit |
| `test_song.lua` | Native-API smoke test: track, Surge XT, ReaEQ, MIDI item, four chords |
| `build.sh` / `run.sh` / `run_test.sh` | One-command build, evaluate, smoke test |
| `workspace/` | Bind-mounted exchange directory; the only host path the container sees |

## Execution sequence

1. `xvfb-run -a reaper -nosplash -ignoreerrors -new /opt/scripts/runner_wrapper.lua`
2. Wrapper removes stale `output.rpp`, `output.wav`, and `error.log`.
3. Wrapper runs `pcall(dofile, "/workspace/agent_song.lua")`.
4. On success it forces master-mix, entire-project, 48 kHz, stereo render
   settings and a fixed target of `/workspace/output.wav`.
5. `Main_SaveProjectEx(0, "/workspace/output.rpp", 8)` saves the project.
6. `Main_OnCommand(42230, 0)` renders offline and auto-closes the render dialog.
7. Wrapper checks both files, clears the project dirty flag, and quits with
   `Main_OnCommand(40004, 0)`.

The dirty flag is cleared on **every** exit path, including Lua failures. This
prevents action 40004 from opening a "save changes?" modal when a model creates
tracks and then calls a nonexistent API.

## Render contract

| Setting | Value |
| --- | --- |
| Target | `/workspace/output.wav` |
| Source | Master mix (`RENDER_SETTINGS=0`) |
| Bounds | Entire project (`RENDER_BOUNDSFLAG=1`) |
| Sample rate | 48000 Hz |
| Channels | 2 (stereo) |
| Format | WAV, REAPER project default depth (24-bit in the smoke test) |
| Tail | None |
| Normalize / dither / add-to-project | Off |

`output.rpp` contains the same render configuration plus the model's tracks,
items, and FX.

## Headless configuration

`reaper.ini` is installed at `/root/.config/REAPER/reaper.ini`:

```ini
[reaper]
linux_audio_mode=3
audiocfgopen=0
splash=0
renderclosewhenelen=1
renderclosewhendone=4
vstpath=/usr/lib/vst3
vstpath64=/usr/lib/vst3
```

REAPER's documentation usually spells the section `[REAPER]`; section names
are case-insensitive, so `[reaper]` is read and preserved as requested.
`linux_audio_mode=3` selects the Dummy Audio backend. `audiocfgopen=0` prevents
the audio-device configuration dialog, and the render-close keys keep action
42230 from waiting on a dialog.

## Plugin cache

The build runs REAPER once under Xvfb. REAPER scans plugins before command-line
scripts run, so `bootstrap_scan.lua` only has to quit with action 40004. The
resulting caches are committed into the image layer:

```text
/root/.config/REAPER/reaper-vstplugins64.ini
/root/.config/REAPER/reaper-clap-linux-x86_64.ini
```

The build fails unless both caches contain Surge XT and Dragonfly Hall Reverb.
Runtime containers use the cache and do not rescan the plugins.

## Container isolation

`run.sh` starts the container with:

```text
--network none --init --pids-limit 512 --memory 4g --shm-size 512m
--cap-drop ALL -v "$PWD/workspace:/workspace" "$REAPER_IMAGE"
```

The Docker command is wrapped in `timeout --signal=TERM --kill-after=10s`
(default 300 s), with an EXIT trap that force-removes the container. This
covers model scripts that block in `reaper.MB` or loop forever.

The container runs as root because REAPER's configuration lives under
`/root/.config/REAPER`. Because all capabilities are dropped, the bind-mounted
`workspace/` must be traversable and writable by the container root; `run.sh`
sets it to `0777` and the input script to `0644`. Files written by REAPER are
owned by root and are readable by the host (`0644`). To reclaim ownership:

```bash
sudo chown -R "$(id -u):$(id -g)" workspace
```

This is process/container isolation, not a VM. The model's Lua can call
`os.execute` inside the container, but it has no network and no host bind mount
other than `workspace/`. For hostile code, add stronger runtime policy
(seccomp, read-only root filesystem, etc.) on top of the included timeout.

## Verified smoke-test result

```text
output.wav: pcm_s24le, 48000 Hz, 2 channels, 8.000000 s, 2,304,690 bytes
output.rpp: 76 KiB, "Surge XT -> ReaEQ", Surge XT VST3i, ReaEQ, 12 MIDI note-ons
audio: mean volume about -26.6 dB, max about -14 dB
wall time: about 3 s (warm plugin cache)
```

## Troubleshooting

- **`Permission denied` on `/workspace`** — ensure `workspace/` is `0777`; the
  container root has no `DAC_OVERRIDE` capability after `--cap-drop ALL`.
- **`error.log` exists but no WAV** — read it; the wrapper exits cleanly and
  leaves no partial output.
- **`Surge XT VST3 was not found`** — rebuild the image so the plugin cache is
  regenerated; do not mount an empty `/root/.config/REAPER` over the image.
- **`LC_NUMERIC ... overriding ... to POSIX`** — harmless REAPER startup
  warning under `C.UTF-8`.
- **Container hangs** — `run.sh` enforces `REAPER_TIMEOUT_SECS` (default 300)
  and removes the container on exit. If a script needs longer, raise it.
