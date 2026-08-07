---
authored_by: agent
type: note
updated: 2026-08-06
status: current
---
# News Digest — References & Inspiration

A survey of existing aggregators, open-source dashboards, design patterns, and source communities the `/news-digest` skill borrows from. All links verified via web search on 2026-06-09.

## 1. Public aggregators / dashboards worth studying

**AI / tech**
- [Techmeme](https://www.techmeme.com/) — Editor + algorithm hybrid that clusters top tech headlines with related-coverage links. Best-in-class "one story, many sources."
- [Hacker News](https://news.ycombinator.com/) — Community firehose; the comments are the product. Pull high-signal via [hnrss.org](https://hnrss.org/) with a points threshold (`hnrss.org/frontpage?points=150`).
- [TLDR AI](https://tldr.tech/ai) — Weekday 5-minute digest; one-paragraph summary + link per item. The item-format model to copy.
- [Ben's Bites](https://news.bensbites.com/) — Builder/founder lens on AI.
- [Techpresso](https://techpresso.co/) — ML detects hot topics, human curates. Good hybrid model.
- [The Batch](https://www.deeplearning.ai/the-batch/) (Andrew Ng) and [Import AI](https://importai.substack.com/) (Jack Clark) — weekly research/policy depth.
- [Ground News](https://ground.news/) — Same-story clustering with source/bias context.

**Design**
- [Sidebar.io](https://sidebar.io/) — 5 hand-picked design links daily. Gold standard for high signal-to-noise; the daily-cap discipline to copy.
- [Smashing Magazine](https://www.smashingmagazine.com/) — Deep web design/dev articles.
- [Designer News](https://www.designernews.co/) — Community-voted links.
- [Dense Discovery](https://www.densediscovery.com/) — Weekly design/tech/culture intersection.
- [Awwwards](https://www.awwwards.com/) — Daily visual inspiration.
- [Creative Bloq](https://www.creativebloq.com/) — Broad design/art news.

## 2. Personal / open-source dashboards & digest tools

**Full pipelines (closest "build your own" references)**
- [iliane5/meridian](https://github.com/iliane5/meridian) — The standout. Scrapes hundreds of sources → embeddings → UMAP/HDBSCAN clustering → LLM cluster review → "presidential daily brief." Study this architecture. Docker fork: [lfzawacki/meridiano](https://github.com/lfzawacki/meridiano).
- [Thysrael/Horizon](https://github.com/Thysrael/Horizon) — Multi-source radar (HN, RSS, Reddit, Telegram, X, GitHub) → AI scores each item 0–10 → dedups same story across platforms → summarizes → GitHub Pages daily brief. Excellent feature checklist.
- [finaldie/auto-news](https://github.com/finaldie/auto-news) — Personal aggregator: Tweets, RSS, YouTube, web, Reddit + LLM (ChatGPT/Gemini/Ollama) to cut noise.

**Self-hosted RSS backbones**
- [FreshRSS](https://github.com/FreshRSS/FreshRSS) — Lightweight, multi-user, XPath scraping for feed-less sites.
- [Miniflux](https://miniflux.app/) — Minimalist Go single-binary reader; strong API/webhooks to bolt AI digests onto.

**AI-digest / morning-brief generators**
- [yinan-c/RSSbrew](https://github.com/yinan-c/RSSbrew) — Aggregate, filter, AI-summarize, roll into daily/weekly digests.
- [00sapo/better-morning](https://github.com/00sapo/better-morning) — TOML feeds → full-content extraction → litellm summaries → GitHub Action → email/Release. Literal morning brief.
- [leozqin/precis](https://github.com/leozqin/precis) — Self-hosted reader focused on AI summaries + notifications.
- [piqoni/matcha](https://github.com/piqoni/matcha) — Daily digest as a **markdown file** for Obsidian/terminal; local-AI friendly. (Closest to this skill's markdown output.)
- [giftedunicorn/ai-news-bot](https://github.com/giftedunicorn/ai-news-bot) — GitHub Actions digest bot; multi-LLM, HTML email, no server.
- [heussd/daily-digest](https://github.com/heussd/daily-digest) — Summarizes each article from 3 angles for a "newspaper" feel.

**Show HN / write-ups**
- [Show HN: Folo](https://news.ycombinator.com/item?id=46033915) — Open-source RSS reader that summarizes your timeline into a daily AI digest.
- [Build Your Own News Feed With a Local LLM, RSS, and Zero Budget](https://medium.com/@vmvini/build-your-own-news-feed-with-a-local-llm-rss-and-zero-budget-ea92931699dc)
- [I made RSS better with Obsidian and a local LLM](https://www.xda-developers.com/made-rss-better-obsidian-summaries-local-llm/) — Matcha-based daily markdown brief workflow.

**Catalog to keep:** [taielab/awesome-ai-news](https://github.com/taielab/awesome-ai-news).

## 3. Design patterns this skill adopts

1. **Cluster, don't list.** Dedup the same story across outlets, show one representative with an "all coverage" expand. The single highest-leverage pattern (what makes Techmeme/Ground News feel calm). → implemented via the `cluster` key + "+N more on this story."
2. **Surface "what changed" at the top.** Lead with new/changed items since last run. → the "New since last digest" rail.
3. **Cap the first screen.** ~5–6 cards, then progressive disclosure. → `first_screen_cap` + collapsible extras.
4. **Thematic panels.** Group by topic into separated zones, not one mixed stream. → AI / Design / AI×Design / Tech sections + filter pills.
5. **Lightweight filtering + search.** Saved topic filters and instant keyword search.
6. **Design the quiet day.** Explicit empty states ("nothing new in this lane") + on-demand run + dated history.

## 4. Source communities (also encoded in `sources.json`)

**Reddit:** r/LocalLLaMA (new model families trend here first), r/MachineLearning, r/artificial, r/ChatGPT, r/PromptEngineering, r/LanguageTechnology, r/computervision, r/UXDesign, r/web_design.

**Forums / aggregators:** [Lobste.rs](https://lobste.rs/) (tag-filterable, high signal), [Hacker News](https://news.ycombinator.com/), [Product Hunt](https://www.producthunt.com/), [UX Stack Exchange](https://ux.stackexchange.com/).

**X / practitioner blogs (primary sources for the AI lens):**
- [Simon Willison](https://simonwillison.net/) ([@simonw](https://x.com/simonw)) — daily hands-on LLM/tooling; has RSS.
- [Latent Space](https://www.latent.space/) (swyx, [@swyx](https://x.com/swyx)) — AI engineering; runs [AINews](https://buttondown.com/ainews).
- [Ahead of AI](https://magazine.sebastianraschka.com/) (Sebastian Raschka) — clearest technical LLM breakdowns.
- [Interconnects](https://www.interconnects.ai/) (Nathan Lambert) — frontier-lab analysis.
- [Eugene Yan](https://eugeneyan.com/) — patterns for building LLM systems & products.
- [Latent Space recommendations](https://www.latent.space/recommendations) — seed list of Substacks to follow.

---

**Build takeaways:** the strongest architecture references are **Meridian** (cluster → brief) and **Horizon** (cross-platform dedup + 0–10 scoring + publish); the strongest UX models are **Techmeme/Ground News** (clustering) and **Sidebar.io/TLDR** (tight cap, one-paragraph items). Most standalone "AI news apps" are just RSS wrappers — the value is in dedup/clustering and the "what changed" framing, which is why this skill prioritizes both over raw breadth.
