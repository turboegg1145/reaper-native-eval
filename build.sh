#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
docker build --pull -t reaper-native-eval:7.85 .
