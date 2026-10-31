# sprout-egress

Egress control for the Sprout agent. This repository holds the **allowlist of domains** Sprout's container may reach, and the **squid proxy configuration** that enforces it.

## The trust model

The allowlist is the one piece of Sprout's infrastructure that is not under Sprout's control — an agent that can edit its own allowlist is guarding itself, which is no guard at all.

- `main` is protected: changes need a pull request with one approval, and a PR author's own approval never counts.
- **Sprout proposes** (pull requests editing `allowed_domains.yaml`).
- **The caregiver / a coalition curator grants** (review and merge).

## Applying a change on the host

After a merge, on the machine running the container:

```sh
~/sprout-egress/reload.sh
```

This pulls, regenerates the flat domain list from the YAML, and runs `squid -k reconfigure` in the sidecar. The proxy reloads in place — no rebuild, no agent restart.

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
| `allowed_domains` | Generated flat list the proxy reads — do not edit by hand |
| `render.sh` | Regenerates the flat list from the YAML |
| `reload.sh` | Host-side: pull, re-render, reload the proxy |
| `squid.conf` | Proxy configuration (includes the flat list) |
| `Containerfile` | The proxy image: Debian + squid, nothing else |
