#!/bin/sh
# ============================================================================
# entrypoint.sh — what the egress proxy container does when it starts.
#
# Two jobs, running side by side for the life of the container:
#
#   Job 1 (foreground-ish): run squid, the actual proxy. The agent's
#   container sends all its web requests here; squid only allows the
#   domains in the allowlist.
#
#   Job 2 (a quiet loop in the background of this script): keep the
#   allowlist current. Every EGRESS_POLL_INTERVAL seconds (default 60) we
#   `git pull` the sprout-harness repository; if allowed_domains.yaml has
#   changed — i.e. the caregiver merged a domain PR — we re-render the flat
#   list squid reads and tell squid to reload its configuration in place.
#
# Result: merging a domain PR is the ONLY action the caregiver ever takes.
# No rebuilds, no restarts, nothing to remember.
# ============================================================================

set -eu   # stop on any error or unset variable

# Where things live inside this container:
SRC=/srv/harness                     # our clone of the sprout-harness repo
CFG="$SRC/egress"                    # the egress/ directory inside that clone
OUT=/etc/squid/allowed_domains       # the flat list squid actually reads

# Which repository to follow, and how often to check it.
# (Defaults are right for normal use; both can be overridden at runtime.)
REPO="${EGRESS_REPO:-https://github.com/sona-coalition/sprout-harness.git}"
INTERVAL="${EGRESS_POLL_INTERVAL:-60}"

# render(): turn the YAML allowlist into the plain one-domain-per-line file
# squid understands. Write to a temp file then move it into place, so squid
# never sees a half-written list.
render() {
    "$CFG/render.sh" "$CFG/allowed_domains.yaml" > "$OUT.new"
    mv "$OUT.new" "$OUT"
}

# --- Startup ---------------------------------------------------------------
# Get the config: clone the repo (first boot) or pull it (container re-run
# against a reused volume — harmless either way).
echo "egress: fetching configuration from $REPO"
git clone -q --depth 1 "$REPO" "$SRC" 2>/dev/null || git -C "$SRC" pull -q --ff-only

# Render the allowlist before squid starts, so squid never runs unconfigured.
render

# Start squid as a background job of this script.
#   -N       run in the foreground of its own process (no daemonising)
#   -d 1     log debugging at level 1 (visible via `podman logs`)
#   -f ...   use this configuration file
echo "egress: starting squid (allowlist poll every ${INTERVAL}s)"
squid -N -d 1 -f "$CFG/squid.conf" &

# Remember the current allowlist version so we can tell when it changes.
CUR=$(md5sum "$CFG/allowed_domains.yaml" | cut -d' ' -f1)

# --- The poll loop ------------------------------------------------------------
# Every INTERVAL seconds: pull the repo. If the YAML changed, re-render and
# reload. `squid -k reconfigure` makes squid re-read its config WITHOUT
# restarting — existing connections are untouched, the agent never notices.
while true; do
    sleep "$INTERVAL"
    git -C "$SRC" pull -q --ff-only 2>/dev/null || continue
    NEW=$(md5sum "$CFG/allowed_domains.yaml" | cut -d' ' -f1)
    [ "$NEW" = "$CUR" ] && continue
    CUR=$NEW
    if render && squid -k reconfigure; then
        echo "egress: allowlist updated and reloaded"
    fi
done
