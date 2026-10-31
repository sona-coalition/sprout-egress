#!/usr/bin/env bash
# ============================================================================
# render.sh — converts the human-reviewed YAML allowlist into the plain
# one-domain-per-line list that squid reads.
#
# Usage:   render.sh [path-to-yaml]     (default: allowed_domains.yaml here)
# Output:  the domain list on stdout (callers redirect where they need it).
#
# The YAML has extra attributes (path_prefix, read_only) that record intent
# in Superconductor's style; the proxy enforces only the domain itself
# (see README). This script deliberately parses just the "- domain:" lines —
# keep the YAML structure simple.
# ============================================================================
set -euo pipefail

YAML="${1:-$(dirname "$0")/allowed_domains.yaml}"

python3 - "$YAML" <<'EOF'
import re, sys

domains = []
with open(sys.argv[1]) as f:
    for line in f:
        line = line.split('#')[0].rstrip()            # strip comments
        m = re.match(r'\s*-\s*domain:\s*(\S+)\s*$', line)
        if m:
            domains.append(m.group(1))

if not domains:
    raise SystemExit('render.sh: no domains found — refusing to render an empty allowlist')

print('\n'.join(domains))
EOF
