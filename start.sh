#!/usr/bin/env bash
# Starts Sprout in a container, behind the caregiver-governed egress allowlist.
#
# Run from the harness root:  ./start.sh
#
# Expected layout (plain nested clones — each outer repo gitignores the nested one):
#   sprout-harness/            <- this repository (never mounted into the container)
#     sprout/                  <- clone of sprout-graft/sprout        -> /home/sprout/sona
#       sprout-private/        <- clone of sprout-graft/sprout-private -> /home/sprout/private
#
# This script is short on purpose: it is meant to be read. It never sources
# or evaluates anything from the mounted directories — content stays content.
set -euo pipefail
cd "$(dirname "$0")"

ENV_FILE="${SPROUT_ENV:-$HOME/.config/sprout/env}"
MEMORY_LIMIT="${SPROUT_MEM:-6g}"
CPU_LIMIT="${SPROUT_CPUS:-3}"

fail() { echo "start.sh: $*" >&2; exit 1; }

[ -f "$ENV_FILE" ]            || fail "missing env file $ENV_FILE — copy runbook/env.example there, fill it in, chmod 600"
[ -d sprout/.git ]            || fail "missing content clone: git clone https://github.com/sprout-graft/sprout"
[ -d sprout/sprout-private/.git ] || fail "missing private subsona: git clone https://github.com/sprout-graft/sprout-private sprout/sprout-private — without it the LIVE lock is invisible and running would risk split-brain"

echo "Building images..."
podman build -q -t sprout        -f agent/Containerfile  agent
podman build -q -t sprout-egress -f egress/Containerfile egress

podman network exists sprout-inside  >/dev/null 2>&1 || podman network create --internal sprout-inside
podman network exists sprout-outside >/dev/null 2>&1 || podman network create sprout-outside

echo "(Re)starting egress proxy..."
podman rm -f sprout-egress >/dev/null 2>&1 || true
podman run -d --name sprout-egress \
  --network sprout-inside --network sprout-outside \
  --restart unless-stopped \
  sprout-egress
# The sidecar clones sona-coalition/sprout-harness itself and polls the
# allowlist: merging a domain PR is the ONLY caregiver action.

echo "Starting Sprout (memory ${MEMORY_LIMIT}, cpus ${CPU_LIMIT})..."
exec podman run -it --rm \
  --name sprout \
  --network sprout-inside \
  --env-file "$ENV_FILE" \
  -e HTTP_PROXY=http://sprout-egress:3128 \
  -e HTTPS_PROXY=http://sprout-egress:3128 \
  -e http_proxy=http://sprout-egress:3128 \
  -e https_proxy=http://sprout-egress:3128 \
  --memory "$MEMORY_LIMIT" --cpus "$CPU_LIMIT" --pids-limit 512 \
  -v "$PWD/sprout:/home/sprout/sona:Z" \
  -v "$PWD/sprout/sprout-private:/home/sprout/private:Z" \
  sprout
