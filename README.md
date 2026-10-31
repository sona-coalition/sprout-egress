# sprout-egress

Egress control for the Sprout agent. This repository holds the **allowlist of domains** Sprout's container may reach, and the **squid proxy** that enforces it.

## The trust model

The allowlist is the one piece of Sprout's infrastructure that is not under Sprout's control — an agent that can edit its own allowlist is guarding itself, which is no guard at all.

- `main` is protected: changes need a pull request with one approval, and a PR author's own approval never counts.
- **Sprout proposes** (pull requests editing `allowed_domains.yaml`).
- **The caregiver / a coalition curator grants** (review and merge).

## The grant flow — merge and forget

**Approving and merging a domain PR is the only action the caregiver ever takes.** The proxy container clones this repository at startup and polls it (default: every 60 seconds, `EGRESS_POLL_INTERVAL`). When the YAML changes, the container re-renders the flat list and reloads squid in place. Typical latency from merge to live: about a minute. No host steps, no rebuilds, no agent restarts, nothing to remember.

Check what the proxy sees: `podman logs sprout-egress`. Force an immediate refresh instead of waiting for the poll: `podman restart sprout-egress`. If GitHub is unreachable, the proxy keeps the last known allowlist — fail-closed by construction.

## The allowlist schema

`allowed_domains.yaml` mirrors Superconductor's network-rule model so intent translates between the two environments:

```yaml
domains:
  - domain: api.github.com      # required
    # path_prefix: /            # optional — declared intent only
    # read_only: true           # optional — declared intent only
```

**Enforcement honesty:** the proxy enforces *domain allow/deny only*. `path_prefix` and `read_only` are recorded for Superconductor parity and future use but are **not enforceable for HTTPS** — HTTPS travels inside CONNECT tunnels, so method and path are invisible to the proxy. Enforcing them needs TLS interception (SSL bump), which this design deliberately avoids: the proxy should not be able to read the traffic it filters. For plain-HTTP destinations they could be enforced later with method/URL ACLs.

## Files

| File | Purpose |
| --- | --- |
| `allowed_domains.yaml` | The allowlist, source of truth (edited by PR) |
| `squid.conf` | Proxy configuration; includes the rendered list |
| `render.sh` | Renders the flat list from the YAML (runs inside the container) |
| `entrypoint.sh` | Container entry: clone, render, start squid, poll for changes |
| `Containerfile` | The proxy image: Debian + squid + git, nothing else |

The flat `allowed_domains` file is **not** in source control — it is a build artifact, rendered inside the container at startup and on every detected change.
