# Egress proxy for the Sprout agent: Debian + squid + git, nothing else.
# At runtime the container clones THIS repository and keeps its allowlist
# current by polling it — see entrypoint.sh and README.md.
FROM debian:trixie-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends squid git ca-certificates python3 \
 && rm -rf /var/lib/apt/lists/*

COPY entrypoint.sh /usr/local/bin/egress-entrypoint.sh
RUN chmod +x /usr/local/bin/egress-entrypoint.sh

EXPOSE 3128
CMD ["egress-entrypoint.sh"]
