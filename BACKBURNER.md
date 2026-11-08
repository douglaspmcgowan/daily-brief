# Backburner

<!-- Park optional or deferred work here. Promote it into TASK.md when authorized and active. -->

<!-- agent-harness:intake:v1:start -->
## Intake - filed by agents working on other projects

> An agent that finds something wrong here while working elsewhere records it and does
> not fix it. This block is where those records land; this project's own agent triages
> them, promotes what it takes to TASK.md, and deletes nothing to make a count look
> better. Written by ``Add-ProjectIntake.ps1`` -- add items with that tool rather than by
> hand, so the id-collision check and the format actually hold.
### app-standard-gaps

**daily-brief App Standard gaps (reader, target polished, stage works not met)**

- **Filed** 2026-11-08 by an agent working on app-standard-sweep
- **Relationship** defect - **Value** high - **Risk** high
- **Evidence** READINESS.md at sweep: npm test fails (tests/floor.spec.js 375px page scrolls sideways, scrollWidth 382 vs 375); keyboard-focus fails (31 links not reached by Tab); error-capture fails (no window error or unhandledrejection listener); seo-tags fails (no canonical, robots.txt, sitemap.xml); PRODUCT.md is an empty template and there is no SPEC.md; no deployed URL recorded so deployed-url is unverified. Gap 1: api/reader.js is unauthenticated, CORS *, fetches any public URL.
- **Fix Recommendation** 1 Rate-limit or restrict api/reader.js (origin allowlist instead of CORS *). 2 Fix horizontal overflow at 375px in build_digest.py CSS. 3 Add window error and unhandledrejection listeners in build_digest.py. 4 Add link rel=canonical in build_digest.py, plus robots.txt and sitemap.xml. 5 Fill PRODUCT.md and add SPEC.md naming core flows. Then run Test-ProductReadiness.ps1 -ProductPath . -Check all -Write -Url http://127.0.0.1:4222.
- **Fix Location** build_digest.py (page CSS and JS), api/reader.js, PRODUCT.md, SPEC.md
- **Fix Rationale** These are the failing checks in READINESS.md; build_digest.py generates index.html so fixes go there, not in the output.
- **CannotFixHere** sweep files the app's own gaps record into its lane worktree by design
- **Queue** .agents/work/imports/intake/queue--20261108T042323662Z--26d22829379e47c083ce448624921e5b.json
<!-- agent-harness:intake:v1:end -->
