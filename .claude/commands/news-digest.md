---
name: news-digest
description: Builds the Daily Brief — interactive AI/Design/Tech news digest. Pulls fresh stories from Gmail + web/RSS/Reddit, merges into persistent corpus.json, renders index.html + digest.html + a markdown note. Topics: AI, Design, AI×Design/Eng, Tech. Run from the repo root.
---

# /news-digest

## Purpose

One calm, scannable brief of what's new across **AI**, **Design**, **AI-in-design/engineering**, and **big Tech/coding** — from newsletters in your inbox plus the best public sources. Keeps a **persistent corpus**: new stories added, stale ones aged out.

Outputs every run:
- `index.html` / `digest.html` — interactive dashboard (topic filters, keyword search, clustering, "new since last run")
- `Latest Digest.md` (+ dated copy in `digests/`) — Obsidian-readable summary

**Scope note:** Personal news, not NASA work. WebFetch/WebSearch are allowed. Do not route through NASA endpoints.

---

## Prerequisites

- **Gmail MCP** must be connected (`search_threads` / `get_thread`). If unavailable, skip Phase 1a and gather from web/RSS only.
- **Python 3.9+** in PATH — `python build_digest.py` must work from the repo root.

---

## Paths

All paths are relative to the **repo root** (your session's working directory).

- `sources.json` — editable source registry (Gmail senders/labels, web/RSS, Reddit, X, forums)
- `corpus.json` — the persistent store. **Read it first** before gathering — existing `id`s and `url`s are your dedup keys.
- `build_digest.py` — deterministic prune + cluster + render. Feed it a good `corpus.json` and run it; don't reimplement it.

---

## Phase 0 — Load state

1. Read `sources.json` and `corpus.json`.
2. Note `corpus.last_run` and the set of existing item `id`s and `url`s.
3. Default lookback: since `last_run` (or 7 days if first run).

---

## Phase 1 — Gather fresh items (parallelize)

You want **individual stories/links**, not the newsletters themselves. A single TLDR email has ~8 stories — extract each one, linking to the actual target URL printed in the email. Never invent a URL.

**Volume = comprehensive.** Don't cap. Pull everything that clears the score bar; the digest stays calm through clustering + progressive disclosure, not by dropping stories.

### 1a. Gmail
For each sender/label in `sources.json.gmail`:
- `search_threads` with `from:<sender> newer_than:<window>`
- For promising threads, `get_thread` with `messageFormat: FULL_CONTENT` — extract headline + real link for each top story

### 1b. Web / RSS
`WebFetch` each `rss` feed in `sources.json.web` and `forums`; fall back to the `url`. Pull items since `last_run`.

### 1c. Reddit / X / forums
- Reddit: `WebFetch` each `.rss` endpoint in `sources.json.reddit`
- X: **corroboration-only** — surface an X post only when a non-X source covers the same story (shared `cluster` key). Standalone X posts are dropped.

**Hard rule:** only include links that actually appear in the source. Drop an item before inventing its URL.

---

## Phase 2 — Normalize, dedup, cluster, score

Merge into `corpus.json` (append new, bump `last_seen` for existing items).

```json
{
  "id": "stable-slug",
  "title": "Headline as written",
  "url": "https://real-target-link",
  "source": "TLDR (email)",
  "source_type": "email|rss|web|reddit|twitter|forum",
  "topic": "ai|design|ai_in_design|tech",
  "topics": ["ai"],
  "summary": "2–4 sentences — full context on what happened and why it matters. Only on cluster leads / score ≥7. Empty string otherwise.",
  "rbtl": "1–2 sentences — the meta story, what this actually signals. Only on cluster leads / score ≥7. Empty string otherwise.",
  "first_seen": "YYYY-MM-DD",
  "cluster": "optional-shared-slug",
  "score": 7,
  "pinned": false
}
```

Rules:
- **Dedup:** url or id already exists → update `last_seen` only, don't duplicate
- **Cluster:** ≥2 sources on the same story → shared `cluster` key. build_digest.py renders a lead + "+N more" expander.
- **Topic routing:** `ai` = models/labs/policy; `design` = UX/visual/tools (non-AI); `ai_in_design` = generative UI, AI design/eng tooling; `tech` = big tech/startups/coding/infra
- **Score:** launches/major moves 7–9; solid reads 5–6; minor 3–4
- **Summaries + RBTL = top stories only.** For cluster leads and items scoring ≥7, write two fields:
  - `summary`: 2–4 sentences. What happened, key details, full context — more depth than a wire-service lede. Ground every claim in the source.
  - `rbtl` ("Reading Between the Lines"): 1–2 sentences on the *meta* story. What this actually signals — the competitive dynamic, the thing the press release doesn't say, the power move buried in the announcement, the implication most coverage will miss. Be direct and analytical; don't hedge into the obvious.
  Everything else ships as headline + source + link with empty `summary` and `rbtl`. build_digest.py renders `rbtl` with a distinct italic style below the summary, only on cluster leads.
- Do **not** set `is_new` — build_digest.py computes it from `first_seen` vs `last_run`

Write the merged corpus back to `corpus.json` (preserve existing `references` array and `retention_days`).

---

## Phase 3 — Render

```bash
python build_digest.py
```

Confirm item/prune counts look sane. Writes `index.html`, `digest.html`, `Latest Digest.md`, `digests/YYYY-MM-DD.md`, and stamps `last_run`.

---

## Phase 4 — Report & open

Output: file path, item count, new count, pruned count, top 3–5 stories. Then open:
- **macOS:** `open index.html`
- **Windows:** `start index.html`
- **Linux:** `xdg-open index.html`

---

## Operating constraints

- **Manual only.** No scheduled tasks, cron jobs, or automatic runs.
- **Never fabricate links, headlines, or numbers.** Drop an item before inventing a URL.
- `corpus.json`, `index.html`, `digest.html`, `Latest Digest.md` are skill-owned generated files — overwriting on each run is expected. Do not touch other files in the vault.
- `sources.json` is user-editable; only change it if explicitly asked.
- If a source is unreachable, skip and note it — never block the whole digest on one feed.
