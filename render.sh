#!/usr/bin/env bash
# Renders the flat squid domain list from allowed_domains.yaml to stdout.
# Usage: render.sh [path-to-yaml]   (default: ./allowed_domains.yaml)
# Parses only "- domain:" lines — keep the YAML structure simple.
set -euo pipefail

YAML="${1:-$(dirname "$0")/allowed_domains.yaml}"

python3 - "$YAML" <<'EOF'
import re, sys

domains = []
with open(sys.argv[1]) as f:
    for line in f:
        line = line.split('#')[0].rstrip()
        m = re.match(r'\s*-\s*domain:\s*(\S+)\s*$', line)
        if m:
            domains.append(m.group(1))

if not domains:
    raise SystemExit('render.sh: no domains found')

print('\n'.join(domains))
EOF
