# Documentation

Start with [`AGENTS.md`](../AGENTS.md) in the repo root — it is the entry point
for both humans and AI agents, and is written to be sufficient context for most
tasks on its own.

This folder holds the detail that `AGENTS.md` deliberately leaves out.

## Layout

```
docs/
├── guides/       How to perform specific operations
├── reference/    How the system is put together
└── strategies/   Per-strategy design and deployment notes
```

## Guides

| Document | Read it when |
|---|---|
| [`guides/PRODUCTION_UPDATES.md`](guides/PRODUCTION_UPDATES.md) | **Changing anything on production.** Shadow-first, verification, nginx, rollback. |
| [`guides/API_DEVELOPMENT.md`](guides/API_DEVELOPMENT.md) | Adding or modifying an API endpoint. |
| [`guides/TROUBLESHOOTING.md`](guides/TROUBLESHOOTING.md) | Something is broken and you need the usual suspects. |
| [`guides/VAULT_DEPLOYMENT.md`](guides/VAULT_DEPLOYMENT.md) | Deploying a new vault. |

## Reference

| Document | Contents |
|---|---|
| [`reference/ARCHITECTURE.md`](reference/ARCHITECTURE.md) | Services, ports, data flow, request lifecycle. |
| [`reference/API.md`](reference/API.md) | Endpoint conventions, parameters, error codes, auth schemes. |

## Strategies

Per-strategy notes live in [`strategies/`](strategies/). Each live strategy runs
as its own PM2 process; see `AGENTS.md` §2 for the process list.

---

## Conventions for these documents

These files are read by AI agents on nearly every task, so they are optimized
for that: state the fact, then the consequence of not knowing it. Avoid
narrating history — a document describing how the system *used to* work costs
tokens on every read and invites an agent to act on a system that no longer
exists. If something is retired, delete the document rather than annotating it.
