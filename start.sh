#!/usr/bin/env bash
# ============================================================================
# start.sh — builds and starts Sprout in a container, behind the egress proxy.
#
# Run it from the harness root:   ./start.sh
#
# What this script does, in order:
#   1. Checks the things it needs are in place (env file, content clones).
#   2. Builds two container images: the agent and the egress proxy.
#   3. Creates two container networks: one with no route out, one with access.
#   4. Starts the egress proxy attached to both networks.
#   5. Starts the agent attached ONLY to the closed network, so its only
#      way to reach the internet is through the proxy.
#
# Expected layout (plain nested clones; each outer repo gitignores the
# nested one, so git never confuses the levels):
#
#   sprout-harness/            <- this repository (NEVER mounted into the container)
#     .env                     <- your secrets file (gitignored; see below)
#     sprout/                  <- clone of sprout-graft/sprout         -> mounted read-write
#       sprout-private/        <- clone of sprout-graft/sprout-private -> mounted read-write
#
# The rule that makes this safe: the harness (this repo, including this
# script) is never visible inside the container, and this script never
# sources or evaluates anything from the mounted directories. Content stays
# content; controls stay outside.
# ============================================================================

set -euo pipefail   # stop on any error, on unset variables, and on pipe failures
cd "$(dirname "$0")"   # work from this script's own directory, wherever it was called from

# --- Settings (override from the environment if ever needed) ---------------
MEMORY_LIMIT="${SPROUT_MEM:-6g}"     # RAM cap for the agent container
CPU_LIMIT="${SPROUT_CPUS:-3}"        # CPU cap for the agent container

# --- 1. Locate the secrets file --------------------------------------------
# Preferred: ./.env in the harness root (gitignored — never committed).
# Fallback: ~/.config/sprout/env. SPROUT_ENV overrides both.
# The file is passed to podman with --env-file, so secret VALUES never
# appear in shell history or in the process list.
if [ -n "${SPROUT_ENV:-}" ]; then
  ENV_FILE="$SPROUT_ENV"
elif [ -f ./.env ]; then
  ENV_FILE="./.env"
else
  ENV_FILE="$HOME/.config/sprout/env"
fi

fail() { echo "start.sh: $*" >&2; exit 1; }

[ -f "$ENV_FILE" ] || fail "missing secrets file: $ENV_FILE
  Create it from runbook/env.example (fill in the four values, chmod 600).
  Put it at ./.env here in the harness root, or at ~/.config/sprout/env."

# If the secrets file lives inside this repository, it must be untracked.
# (A tracked .env would mean secrets had been committed — stop immediately.)
if [ "$ENV_FILE" = "./.env" ] && git ls-files --error-unmatch .env >/dev/null 2>&1; then
  fail ".env is tracked by git — secrets must never be committed. Remove it from git history first."
fi

# --- 2. Check the content clones -------------------------------------------
# The agent reads its identity and memory from these two repositories.
[ -d sprout/.git ] || fail "missing content clone:
  git clone https://github.com/sprout-graft/sprout"

# The private subsona holds the LIVE lock. Without it this instance cannot
# know whether another Sprout is already running elsewhere — running anyway
# would risk two live instances (split-brain; see runbook §7).
[ -d sprout/sprout-private/.git ] || fail "missing private subsona:
  git clone https://github.com/sprout-graft/sprout-private sprout/sprout-private"

# --- 3. Build the images ----------------------------------------------------
# -q keeps the output quiet; podman caches layers, so rebuilds are fast.
echo "Building images..."
podman build -q -t sprout        -f agent/Containerfile  agent
podman build -q -t sprout-egress -f egress/Containerfile egress

# --- 4. Create the networks -------------------------------------------------
# sprout-inside is "internal": containers on it have NO route to the internet
# or to the host's local network. sprout-outside is a normal network.
# `podman network exists` makes these lines safe to run repeatedly.
podman network exists sprout-inside  >/dev/null 2>&1 || podman network create --internal sprout-inside
podman network exists sprout-outside >/dev/null 2>&1 || podman network create sprout-outside

# --- 5. (Re)start the egress proxy ------------------------------------------
# The proxy sits on BOTH networks: it can reach the internet, and the agent
# can reach it. It clones sona-coalition/sprout-harness itself and polls the
# allowlist — so merging a domain PR is the ONLY thing the caregiver does.
echo "(Re)starting egress proxy..."
podman rm -f sprout-egress >/dev/null 2>&1 || true
podman run -d --name sprout-egress \
  --network sprout-inside --network sprout-outside \
  --restart unless-stopped \
  sprout-egress

# --- 6. Start the agent ------------------------------------------------------
# Key points:
#   --network sprout-inside   the agent has no direct route out; the proxy
#                             (HTTP_PROXY/HTTPS_PROXY) is its only path.
#   --env-file                secrets arrive from the file, not the shell.
#   --memory/--cpus/--pids    a runaway agent cannot take the host down.
#   -v ... :Z                 mounts the two content clones read-write,
#                             relabelled so SELinux hosts allow access.
#                             Mount paths MIRROR the host layout — same
#                             path inside the container as outside it.
# `exec` replaces this script with the podman process, so stopping the
# container (Ctrl-C) ends the script cleanly. --rm tidies up on exit.
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
  -v "$PWD/sprout:/home/sprout/sprout:Z" \
  -v "$PWD/sprout/sprout-private:/home/sprout/sprout/sprout-private:Z" \
  sprout
