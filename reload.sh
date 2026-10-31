#!/usr/bin/env bash
# Host-side: apply a merged allowlist change to the running proxy.
# Usage: ~/sprout-egress/reload.sh
set -euo pipefail
cd "$(dirname "$0")"

git pull --ff-only
./render.sh
podman exec sprout-egress squid -k reconfigure

echo "egress allowlist reloaded (no rebuild, no agent restart)"
