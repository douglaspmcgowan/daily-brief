# Work log

<!-- Append: YYYY-MM-DD | completed work | verifier or evidence -->

## 2026-09-26 | App repair program, stage 1 — BEFORE

Verdict from `APP-REPAIR-SPEC.md`: **BASELINE**. Branch `agent/daily-brief-repair`, worktree
`C:\Users\dougl\Worktrees\daily-brief\repair`, cut from `master` at `5836b04`.

### It works before it was touched

Every command run on the Windows host, Git Bash, 2026-09-26. Node v24.13.1, npm 11.8.0, Python 3.13.15.

| Step | Command | Exit | Result |
|---|---|---|---|
| install | `npm install --no-audit --no-fund` | 0 | 64 packages in 5s |
| audit | `npm audit --audit-level=critical` | 0 | 2 advisories, 1 high, 1 low, **zero critical**. High: `form-data` CRLF injection, GHSA-hmw2-7cc7-3qxx, transitive under `jsdom` |
| build | `python build_digest.py --root <worktree>` | 0 | `10 items kept, 101 pruned. Wrote digest.html, Latest Digest.md, digests/2026-09-26.md` |
| start | `npm start` (`python -m http.server 8787 --bind 127.0.0.1`) | serving | `HTTP 200`, 246257 bytes at `http://127.0.0.1:8787/` |
| render | Browser pane at `http://127.0.0.1:8787/` | — | Renders. 80 `.item` cards, 5 topic pills, 215 links, 411 buttons, 11 `details`, 1 search input |

The build's output was reverted (`git restore --source=HEAD --worktree`) so the branch starts
byte-identical to `master`. `digests/2026-09-26.md` remains untracked: deleting it was refused by the
host permission classifier, and it is regenerable build output, so it was left in place rather than
worked around.

**The build is wall-clock dependent and the corpus is stale.** `build_digest.py` prunes on today's date
against `retention_days`; the committed corpus was last refreshed 2026-06-15, so a rebuild today keeps 10
pinned items and prunes 101. The 246 KB page that renders is the June 15 render. Rebuilding before
refreshing the corpus empties the product. Recorded in `README.md`.

### Baseline floor row

Appendix A `m4.sh`, run against the worktree, `git ls-files` scoped, `/.agents/` excluded:

```
stylefiles=2 KB=481 unique-hex=22 font-sizes=23 custom-props=8 transition=32 @keyframes=2
!important=4 :focus-visible=0 prefers-color-scheme=0 prefers-reduced-motion=0 @container=0 clamp(=0
```

The roster row in `APP-REPAIR-SPEC.md` reads `22/23/8/4/0/0`. It reproduces exactly.

`stylefiles=2` is `index.html` and `digest.html`, which are byte-identical (`cmp` reports no difference)
and are both generated. `!important=4` is 2 occurrences counted twice — `.read-btn:hover` and
`.dismiss-btn:hover`, at `build_digest.py:429` and `:438`.

### Where the CSS actually lives

**Not in any `.css` file and not in `index.html`.** The whole stylesheet and the whole browser script are
Python f-strings inside `build_digest.py`, roughly lines 300–600. `index.html` and `digest.html` are
generated output. Every floor change in stage 2 lands in `build_digest.py` and is proven by regenerating.

Dark mode is half-built already: `PALETTE_DARK` and an `html[data-theme="dark"]` block exist at
`build_digest.py:508`, driven by a localStorage toggle. What is missing is the
`@media (prefers-color-scheme: dark)` hook, so the page ignores the operating system preference until
the user clicks. That is the B4 gap, and it is a hook onto tokens that already exist.

### Computed-style baseline, for the stage 2 token proof

`getComputedStyle` at `http://127.0.0.1:8787/`, 1280x900. Stage 2's token extraction must reproduce this
exactly or it was not a non-visual change.

| Selector | color | background | font-size | radius | padding |
|---|---|---|---|---|---|
| `body` | `rgb(29, 26, 22)` | `rgb(246, 243, 236)` | 16px | 0px | 0px |
| `header.mast` | `rgb(29, 26, 22)` | `rgba(0, 0, 0, 0)` | 16px | 0px | 34px 0px 16px |
| `.mast-title` | `rgb(29, 26, 22)` | `rgba(0, 0, 0, 0)` | 54px | 0px | 0px |
| `.pill` (active) | `rgb(246, 243, 236)` | `rgb(29, 26, 22)` | 13.5px | 999px | 6px 12px |
| `.item` | `rgb(29, 26, 22)` | `rgb(255, 253, 248)` | 16px | 10px | 14px 16px |
| `.title` | `rgb(29, 26, 22)` | `rgba(0, 0, 0, 0)` | 18px | 0px | 0px |
| `.topic-h` | `rgb(29, 26, 22)` | `rgba(0, 0, 0, 0)` | 26px | 0px | 0px 0px 6px |
| `#q` | `rgb(29, 26, 22)` | `rgb(255, 253, 248)` | 16px | 8px | 7px 12px |
| `.whatsnew` | `rgb(29, 26, 22)` | `rgb(243, 221, 212)` | 16px | 12px | 16px 20px |

Resolved `:root` tokens: `--paper #f6f3ec`, `--card #fffdf8`, `--ink #1d1a16`, `--muted #6b6357`,
`--rule #e3ddd0`, `--anchor #c8482b`, `--anchor-soft #f3ddd4`, `--link #1b4d6b`.

### Stack, slot by slot

An empty slot is the finding, not an omission.

| Slot | Occupant |
|---|---|
| language | Python 3 (`build_digest.py`, 1258 lines) and JavaScript (`api/reader.js`, CommonJS; plus one large inline browser script emitted by the generator). **No TypeScript, no `tsconfig.json`.** |
| framework / build | **Empty.** No bundler, no framework, no build step in `package.json`. A Python script writes HTML. |
| UI library | **Empty.** Vanilla DOM. |
| headless primitives | **Empty.** |
| component source | **Empty.** Markup is Python f-strings. |
| styling | Hand-written CSS inside the generator. 8 custom properties on `:root`, plus an `html[data-theme="dark"]` override block. **No Tailwind.** |
| state | **Empty.** `localStorage` for the theme, saved and dismissed items. |
| motion | 32 `transition` declarations, 2 `@keyframes`, **zero `prefers-reduced-motion`**. |
| data | Plain files: `corpus.json` (97 KB), `sources.json`, `digests/*.md`. No database. |
| server | One Vercel serverless function, `api/reader.js`, on `@mozilla/readability` and `jsdom`. SSRF guard present: loopback, link-local and RFC-1918 hosts refused. |
| host | Vercel, `vercel.json` `{"version": 2}`, static. Hosted, so a second person can open it. |
| tests | **Empty.** No Playwright, no test runner, no test directory. |
| CI | GitHub Actions, gitleaks 8.30.1 pinned by SHA-256, on push and pull request. Nothing else. |
| runtime pins | `engines.node >= 18` — a dead major. **No `.nvmrc`, no `.python-version`.** |
| dependency pins | `@mozilla/readability ^0.5.0`, `jsdom ^24.1.0`. Two floating carets, no `latest`. |

### Carried into stage 2

1. Floor gaps: `:focus-visible` 0, `prefers-reduced-motion` 0, `prefers-color-scheme` 0, `!important` 2, all in `build_digest.py`.
2. Runtime pins: raise the dead `>=18` floor, add `.nvmrc` and `.python-version`.
3. Dependency pins: two floating carets to exact versions; re-run `npm audit` after.
4. TypeScript: `api/reader.js` is the only source file in scope — one file, CommonJS, no build step.
5. Tests: no Playwright suite exists, so the axe assertion needs one created.
6. **Do not add a `build` script to `package.json`.** Vercel auto-runs a `build` script for a project with no framework preset, and `python build_digest.py` on a deploy would prune the stale corpus and ship an empty page. `start` was added; `build` deliberately was not.
