# News Digest

An interactive, self-updating brief of **AI · Design · AI-in-Design/Engineering · Tech/Coding** news, built from your news emails plus curated public sources. It is a static page — a Python script renders `index.html`, and Vercel serves that page plus one serverless reader endpoint.

## Start it

```
npm start
```

That serves the already-rendered digest at <http://127.0.0.1:8787/> (it is `python -m http.server 8787 --bind 127.0.0.1`, so Python 3 is the only requirement). Open that address; the page is the product.

Two commands sit behind it, and neither is needed just to look at the digest:

| Command | What it does | When you need it |
|---|---|---|
| `npm install` | Installs `jsdom` and `@mozilla/readability` | Only for `api/reader.js`, the in-page article reader, which runs on Vercel rather than locally |
| `python build_digest.py` | Re-renders `index.html`, `digest.html` and `Latest Digest.md` from `corpus.json` | After new stories land in the corpus |
| `npm test` | Playwright: `axe` on the primary surface, the keyboard focus ring, light and dark from the OS preference, reduced motion | After any change to the page's CSS or browser JavaScript |
| `npm run typecheck` | `tsc --noEmit` over `api/reader.js` under `checkJs` + `strict` | After any change to the reader endpoint |

Runtimes are pinned: `.nvmrc` (Node 22, matching `engines.node`) and `.python-version` (3.13).
There is deliberately **no `build` script** — Vercel would run it on deploy and re-render the page
against a stale corpus. See the note below.

**`build_digest.py` prunes by wall-clock date.** Running it against a corpus older than its retention windows drops almost everything: on 2026-09-26 a rebuild of the 2026-06-15 corpus kept 10 items and pruned 101. Refresh the corpus first, through `/news-digest` in Claude Code, or the rebuild will empty the page.

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
| `index.html` | The same bytes as `digest.html`. This is what Vercel serves at the root URL. |
| `build_digest.py` | Deterministic prune + cluster + render. Standard library only. **It also holds every line of the page's CSS and browser JavaScript** — edit the page here, never in `index.html`, which is generated output. |
| `api/reader.js` | Vercel serverless function behind the in-page reader. Fetches an article, extracts it with Readability, refuses internal and loopback hosts. |
| `References & Inspiration.md` | The research: public dashboards + open-source projects to borrow from, with links. |

## Tuning
- **Add a source:** edit `sources.json` (each entry has a `topics` tag and a `weight`). Ask `/news-digest` to add one and it will.
- **Keep stories longer/shorter:** edit `retention_days` in `sources.json` (`default` 14, `design` 21, `ai_in_design` 30, evergreen/pinned 90).
- **Pin an evergreen source** so it never ages out: set `"pinned": true` on its corpus item.

## Notes
- This is **personal** news — the skill uses the open web (WebFetch/WebSearch). It is deliberately kept out of any NASA/ITAR/CUI path.
- The skill lives at `~/.claude/commands/news-digest.md`. If you want it version-controlled, copy it into `claude-global-config/commands/` alongside your other skills.
- The repository lives at `C:\Users\dougl\Projects\daily-brief` and pushes to `github.com/douglaspmcgowan/daily-brief`. `build_digest.py --root <folder>` renders somewhere else if you want it to.
