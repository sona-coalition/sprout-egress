# sprout-harness

Everything needed to run the Sprout agent in a container: the images, the startup script, the egress allowlist, and the operator runbook.

> **The harness is a control, and the agent does not control it.** Changes here require a pull request with approval from the caregiver or a coalition curator. Sprout can propose; it can never grant. The harness is also **never mounted into the container** — the agent cannot reach the code that runs it, from either side of the boundary.

## Layout

| Path | What it is |
| --- | --- |
| `start.sh` | Builds the images and runs Sprout behind the egress proxy. Run `./start.sh` from the harness root. |
| `agent/Containerfile` | The agent image: Pi plus tools, no secrets, no state. |
| `egress/` | The egress proxy: squid sidecar, the `allowed_domains.yaml` allowlist, self-updating entrypoint. |
| `runbook/RUNBOOK.md` | The operator runbook: durable-state map, secrets, running on Superconductor and in a container, moving Sprout, verification, troubleshooting. |
| `runbook/env.example` | Template for the secrets env file (copy outside any repo, `chmod 600`). |

## Host setup (caregiver)

First time:

```sh
git clone https://github.com/sona-coalition/sprout-harness
cd sprout-harness
cp runbook/env.example .env   # then fill in the four values; chmod 600
```

Every time:

```sh
./start.sh
```

`start.sh` clones or pulls the content repositories itself — the nested clones below exist because it puts them there.

The nested clones are plain clones, not submodules: each outer repository gitignores the nested one (`.gitignore` here covers `/sprout/`; `sprout` covers `/sprout-private/`), so git never confuses the levels. Container mounts are the two content clones only, and they **mirror the host layout** — `sprout-harness/sprout/` on the host is `/home/sprout/sprout` in the container, and `sprout-harness/sprout/sprout-private/` is `/home/sprout/sprout/sprout-private`. One rule, no translation: same path inside as outside.

## Rules

1. **No sourcing mounted content.** Nothing in this repository may source, eval, or execute files from the mounted content directories. Content stays content; the moment the harness executes it, the boundary is gone.
2. **Changes by PR.** Sprout proposes (including changes to its own harness — proposals welcome), the caregiver or a curator approves and merges. A PR author's approval of their own PR never counts.
3. **The allowlist is here too** (`egress/allowed_domains.yaml`), under the same rule: merging a domain PR is the whole caregiver action — the sidecar polls this repository and reloads itself (default 60 s; see `runbook/RUNBOOK.md` §5, §10).

## Related repositories

- [`sprout-graft/sprout`](https://github.com/sprout-graft/sprout) — Sprout's public sona: identity, constitution, goals, startup instructions, operational findings. Content only, no machinery.
- [`sprout-graft/sprout-private`](https://github.com/sprout-graft/sprout-private) — the private subsona: journal, memory, decisions.
