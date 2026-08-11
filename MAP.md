# Project map

## Core documents

| File | Owns |
|---|---|
| `AGENTS.md` | Portable project behavior |
| `CLAUDE.md` | Claude import |
| `.cursor/rules/00-project-contract.mdc` | Cursor project pointer |
| `TASK.md` | Active goal, queue, blockers, completed evidence, next verifier |
| `LOG.md` | Append-only completed work |
| `BACKBURNER.md` | Parked work |
| `MAP.md` | This architecture and navigation map, plus durable capability state |
| `DESIGN.md` | Universal and project interface rules |
| `PRODUCT.md` | Optional product intent |
| `MEMORY.md` | Lean durable-reference index |
| `skills-manifest.json` | Canonical skill bindings |
| `data-manifest.yaml` | External-data authorities, adapters, and restore rules |
| `secret-manifest.json` | Value-free secret inventory and trust boundaries |

## Architecture

| Component | Purpose | Entry point | Owner |
|---|---|---|---|
| `<component>` | `<purpose>` | `<path or command>` | `<owner>` |

## Important paths

| Path | Purpose | Generated | Committed |
|---|---|---|---|
| `<path>` | `<purpose>` | `<yes/no>` | `<yes/no>` |

## Data flow

Describe inputs, transformations, stores, outputs, and trust-boundary crossings.

## Integrations

| System | Direction | Credential name | Failure behavior |
|---|---|---|---|
| `<system>` | `<in/out/both>` | `<name only>` | `<behavior>` |

## Ownership and concurrency

Record component owners, shared mutable resources, worktree constraints, ports, test databases, and deployment targets.

## Update rule

Update this file when a component boundary, data flow, owner, integration, core document, or important path changes.
