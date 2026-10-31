#!/usr/bin/env bash
# Regenerates allowed_domains (flat list read by squid) from allowed_domains.yaml.
# Parses only "- domain:" lines — keep the YAML structure simple.
set -euo pipefail
cd "$(dirname "$0")"

python3 - <<'EOF'
import re

domains = []
with open('allowed_domains.yaml') as f:
    for line in f:
        line = line.split('#')[0].rstrip()
        m = re.match(r'\s*-\s*domain:\s*(\S+)\s*$', line)
        if m:
            domains.append(m.group(1))

if not domains:
    raise SystemExit('render.sh: no domains found in allowed_domains.yaml')

with open('allowed_domains', 'w') as f:
    f.write('\n'.join(domains) + '\n')

print(f'allowed_domains: regenerated with {len(domains)} domains')
EOF
