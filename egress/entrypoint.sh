#!/bin/sh
# Egress proxy entrypoint: squid plus a self-updating allowlist.
#
# The proxy clones this repository, renders the allowlist from
# allowed_domains.yaml, and then polls the repository. When the YAML
# changes (i.e. the caregiver merged a domain PR), it re-renders and
# reloads squid in place. The caregiver's only action is the merge.
set -eu

SRC=/srv/harness
CFG="$SRC/egress"
OUT=/etc/squid/allowed_domains
REPO="${EGRESS_REPO:-https://github.com/sona-coalition/sprout-harness.git}"
INTERVAL="${EGRESS_POLL_INTERVAL:-60}"

render() {
    "$CFG/render.sh" "$CFG/allowed_domains.yaml" > "$OUT.new"
    mv "$OUT.new" "$OUT"
}

echo "egress: fetching allowlist from $REPO"
git clone -q --depth 1 "$REPO" "$SRC" 2>/dev/null || git -C "$SRC" pull -q --ff-only
render

echo "egress: starting squid (poll every ${INTERVAL}s)"
squid -N -d 1 -f "$CFG/squid.conf" &

CUR=$(md5sum "$CFG/allowed_domains.yaml" | cut -d' ' -f1)
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
