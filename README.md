# News Digest

An interactive, self-updating brief of **AI · Design · AI-in-Design/Engineering · Tech/Coding** news, built from your news emails plus curated public sources.

Run it with **`/news-digest`** in Claude Code.

## What each run does
1. Reads `corpus.json` (the persistent store) so it won't re-add what's already there.
2. Pulls fresh stories since the last run — your Gmail newsletters (via the Gmail connector) + web/RSS + Reddit/X/forums listed in `sources.json`.
3. Merges them in: adds new stories, clusters same-story coverage, tags topic + importance, bumps "last seen" on anything still circulating.
4. Runs `build_digest.py`, which **prunes stale items** (per-topic retention), flags what's new, and renders the outputs.

## Files
| File | What it is |
|---|---|
| `digest.html` | The interactive dashboard — topic filters, keyword search, story clusters, "new since last digest." Open in any browser. |
| `Latest Digest.md` | Markdown summary for Obsidian (also archived dated in `digests/`). |
| `corpus.json` | The persistent corpus. Stories live here until they age out; `pinned` evergreen sources stay. |
| `sources.json` | **Your editable source registry.** Add/remove email senders, feeds, subreddits, X accounts. |
| `build_digest.py` | Deterministic prune + cluster + render. No external dependencies. |
| `References & Inspiration.md` | The research: public dashboards + open-source projects to borrow from, with links. |

## Tuning
- **Add a source:** edit `sources.json` (each entry has a `topics` tag and a `weight`). Ask `/news-digest` to add one and it will.
- **Keep stories longer/shorter:** edit `retention_days` in `sources.json` (`default` 14, `design` 21, `ai_in_design` 30, evergreen/pinned 90).
- **Pin an evergreen source** so it never ages out: set `"pinned": true` on its corpus item.

## Notes
- This is **personal** news — the skill uses the open web (WebFetch/WebSearch). It is deliberately kept out of any NASA/ITAR/CUI path.
- The skill lives at `~/.claude/commands/news-digest.md`. If you want it version-controlled, copy it into `claude-global-config/commands/` alongside your other skills.
- The folder currently sits inside the vault for Obsidian convenience; nothing stops you moving it elsewhere — just update the paths in the command file and `build_digest.py`'s `--root`.
