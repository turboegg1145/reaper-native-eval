#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ $# -ne 1 ]]; then
    echo "usage: $0 path/to/agent_song.lua" >&2
    exit 2
fi

mkdir -p workspace
# The container runs as root with all capabilities dropped. A bind-mounted
# 0700 workspace would be untraversable in that mode, so make this dedicated
# sandbox directory traversable/writable and the input world-readable.
chmod 0777 workspace
if [[ "$(readlink -f "$1")" != "$(readlink -f workspace/agent_song.lua)" ]]; then
    cp "$1" workspace/agent_song.lua
fi
chmod 0644 workspace/agent_song.lua
rm -f workspace/output.rpp workspace/output.wav workspace/error.log

TIMEOUT_SECS="${REAPER_TIMEOUT_SECS:-300}"
if [[ ! "$TIMEOUT_SECS" =~ ^[0-9]+$ ]] || [[ "$TIMEOUT_SECS" -lt 1 ]]; then
    echo "REAPER_TIMEOUT_SECS must be a positive integer" >&2
    exit 2
fi

CONTAINER="reaper-eval-$$"
cleanup() {
    docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
}
trap cleanup EXIT

set +e
timeout --signal=TERM --kill-after=10s "${TIMEOUT_SECS}s" \
    docker run --rm \
    --name "$CONTAINER" \
    --network none \
    --init \
    --pids-limit 512 \
    --memory 4g \
    --shm-size 512m \
    --cap-drop ALL \
    -v "$PWD/workspace:/workspace" \
    reaper-native-eval:7.85
rc=$?
set -e

if [[ $rc -eq 124 || $rc -eq 137 ]]; then
    echo "evaluation timed out after ${TIMEOUT_SECS}s" >&2
    exit 1
fi
if [[ $rc -ne 0 ]]; then
    echo "container failed with exit code $rc" >&2
    exit "$rc"
fi

# REAPER itself exits 0 even when runner_wrapper catches a Lua error. Make the
# one-click harness report failure by contract instead of only by log file.
if [[ -s workspace/error.log ]]; then
    echo "evaluation failed; see workspace/error.log" >&2
    exit 1
fi
if [[ ! -s workspace/output.wav || ! -s workspace/output.rpp ]]; then
    echo "evaluation failed: output.wav and/or output.rpp missing" >&2
    exit 1
fi
