# Egress proxy for the Sprout agent: Debian + squid, nothing else.
# Config is mounted at runtime (read-only), never baked in — see README.md.
FROM debian:trixie-slim

RUN apt-get update \
 && apt-get install -y --no-install-recommends squid \
 && rm -rf /var/lib/apt/lists/*

EXPOSE 3128
CMD ["squid", "-N", "-d", "1", "-f", "/etc/squid/egress/squid.conf"]
