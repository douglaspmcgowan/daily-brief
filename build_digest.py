#!/usr/bin/env python3
"""
build_digest.py - prune the persistent news corpus and render the digest.

This is the deterministic half of /news-digest. The agent (Claude) gathers new
items from Gmail + the web and writes them into corpus.json; this script then:
  1. prunes items past their topic's retention window (pinned items are kept),
  2. dedups + clusters items that cover the same story,
  3. renders a self-contained interactive digest.html,
  4. writes a markdown summary (Latest Digest.md + a dated archive copy).

Usage:
    python build_digest.py            # build from ./corpus.json + ./sources.json
    python build_digest.py --root "<folder>"

No third-party deps. Python 3.9+.
"""

from __future__ import annotations
import argparse
import datetime as dt
import html
import json
import os
from collections import defaultdict

TOPICS = ["ai", "design", "ai_in_design", "tech"]
TOPIC_LABELS = {
    "ai": "AI",
    "design": "Design",
    "ai_in_design": "AI × Design / Eng",
    "tech": "Tech & Coding",
}

# --- editorial palette (one bold anchor; no purple gradients, no left accent bars) ---
PALETTE = {
    "paper": "#f6f3ec",
    "card": "#fffdf8",
    "ink": "#1d1a16",
    "muted": "#6b6357",
    "rule": "#e3ddd0",
    "anchor": "#c8482b",   # single warm anchor used for masthead + NEW badge
    "anchor_soft": "#f3ddd4",
    "link": "#1b4d6b",
}

PALETTE_DARK = {
    "paper": "#1c1914",
    "card": "#252017",
    "ink": "#ede9e0",
    "muted": "#9a9088",
    "rule": "#3b342a",
    "anchor": "#e06750",
    "anchor_soft": "#3a1f14",
    "link": "#79b8d8",
}


def today() -> dt.date:
    return dt.date.today()


def parse_date(s, default=None):
    if not s:
        return default
    try:
        return dt.date.fromisoformat(str(s)[:10])
    except ValueError:
        return default


def retention_for(item, retention_cfg):
    if item.get("pinned") or item.get("evergreen"):
        return retention_cfg.get("evergreen", 90)
    topic = item.get("topic", "tech")
    return retention_cfg.get(topic, retention_cfg.get("default", 14))


def load_json(path, fallback):
    if not os.path.exists(path):
        return fallback
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def prune(items, retention_cfg, run_date):
    kept, dropped = [], 0
    for it in items:
        last_seen = parse_date(it.get("last_seen") or it.get("first_seen"), run_date)
        age = (run_date - last_seen).days
        if age > retention_for(it, retention_cfg) and not it.get("pinned"):
            dropped += 1
            continue
        kept.append(it)
    return kept, dropped


def score(item):
    base = item.get("score")
    if base is None:
        base = 5
    return base + item.get("weight", 1)


def cluster_items(items):
    """Group items in one topic by their 'cluster' key (or unique id)."""
    groups = defaultdict(list)
    for it in items:
        key = it.get("cluster") or it.get("id") or it.get("url") or it.get("title")
        groups[key].append(it)
    clusters = []
    for key, members in groups.items():
        members.sort(key=score, reverse=True)
        clusters.append({"key": key, "lead": members[0], "members": members})
    clusters.sort(key=lambda c: (any(m.get("is_new") for m in c["members"]),
                                 score(c["lead"])), reverse=True)
    return clusters


# ----------------------------------------------------------------------------- HTML

def esc(s):
    return html.escape(str(s or ""))


def render_item_html(it, lead=True):
    new_badge = '<span class="badge">NEW</span>' if it.get("is_new") else ""
    src = esc(it.get("source", ""))
    stype = esc(it.get("source_type", ""))
    title = esc(it.get("title", "(untitled)"))
    url = esc(it.get("url", "#"))
    summary = esc(it.get("summary", ""))
    pin = '<span class="pin" title="pinned / evergreen">★</span>' if it.get("pinned") else ""
    cls = "item lead" if lead else "item also"
    search_blob = esc(" ".join([it.get("title", ""), it.get("summary", ""),
                                it.get("source", ""), " ".join(it.get("topics", []))])).lower()
    summ_html = f'<p class="summary">{summary}</p>' if (summary and lead) else ""
    return f"""<article class="{cls}" data-search="{search_blob}">
  <div class="item-head">
    <a class="title" href="{url}" target="_blank" rel="noopener">{title}</a>
    {new_badge}{pin}
  </div>
  <div class="meta"><span class="src">{src}</span><span class="dot">·</span><span class="stype">{stype}</span></div>
  {summ_html}
</article>"""


def render_cluster_html(cluster):
    lead = cluster["lead"]
    parts = [render_item_html(lead, lead=True)]
    extras = cluster["members"][1:]
    if extras:
        also = "".join(
            f'<li><a href="{esc(m.get("url","#"))}" target="_blank" rel="noopener">{esc(m.get("title",""))}</a>'
            f' <span class="also-src">{esc(m.get("source",""))}</span></li>'
            for m in extras
        )
        parts.append(
            f'<details class="also-wrap"><summary>+ {len(extras)} more on this story</summary>'
            f'<ul class="also-list">{also}</ul></details>'
        )
    return f'<div class="cluster">{"".join(parts)}</div>'


def render_references_html(references):
    if not references:
        return ""
    rows = "".join(
        f'<li><a href="{esc(r.get("url","#"))}" target="_blank" rel="noopener">{esc(r.get("name",""))}</a>'
        f' &mdash; <span class="ref-note">{esc(r.get("note",""))}</span></li>'
        for r in references
    )
    return f"""<section class="references">
  <h2>Reference dashboards &amp; inspiration</h2>
  <p class="ref-lead">Public aggregators and personal projects worth borrowing from. Full write-up in <code>References &amp; Inspiration.md</code>.</p>
  <ul class="ref-list">{rows}</ul>
</section>"""


def build_html(corpus, run_date):
    items = corpus.get("items", [])
    references = corpus.get("references", [])
    by_topic = {t: [] for t in TOPICS}
    for it in items:
        t = it.get("topic", "tech")
        by_topic.setdefault(t, []).append(it)

    new_count = sum(1 for it in items if it.get("is_new"))

    # topic sections
    sections = []
    counts = {}
    for t in TOPICS:
        clusters = cluster_items(by_topic.get(t, []))
        counts[t] = sum(len(c["members"]) for c in clusters)
        if not clusters:
            body = '<p class="empty">Nothing new in this lane right now.</p>'
        else:
            body = "".join(render_cluster_html(c) for c in clusters)
        sections.append(
            f'<section class="topic" data-topic="{t}">'
            f'<h2 class="topic-h">{esc(TOPIC_LABELS[t])} '
            f'<span class="count">{counts[t]}</span></h2>{body}</section>'
        )

    # "what's new" rail
    new_items = sorted([it for it in items if it.get("is_new")], key=score, reverse=True)[:8]
    if new_items:
        new_rows = "".join(
            f'<li><a href="{esc(it.get("url","#"))}" target="_blank" rel="noopener">{esc(it.get("title",""))}</a>'
            f' <span class="new-src">{esc(it.get("source",""))} · {esc(TOPIC_LABELS.get(it.get("topic","tech"),""))}</span></li>'
            for it in new_items
        )
        whats_new = f'<section class="whatsnew"><h2>New since last digest</h2><ol>{new_rows}</ol></section>'
    else:
        whats_new = ""

    pills = "".join(
        f'<button class="pill" data-filter="{t}">{esc(TOPIC_LABELS[t])} '
        f'<span class="pc">{counts[t]}</span></button>'
        for t in TOPICS
    )

    refs_html = render_references_html(references)
    stamp = run_date.strftime("%A, %B %-d, %Y") if os.name != "nt" else run_date.strftime("%A, %B %d, %Y")

    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>News Digest — {stamp}</title>
<style>
  :root {{
    --paper:{PALETTE['paper']}; --card:{PALETTE['card']}; --ink:{PALETTE['ink']};
    --muted:{PALETTE['muted']}; --rule:{PALETTE['rule']}; --anchor:{PALETTE['anchor']};
    --anchor-soft:{PALETTE['anchor_soft']}; --link:{PALETTE['link']};
  }}
  * {{ box-sizing:border-box; }}
  body {{ margin:0; background:var(--paper); color:var(--ink);
    font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",Inter,Roboto,Helvetica,Arial,sans-serif;
    line-height:1.5; }}
  .wrap {{ max-width:1080px; margin:0 auto; padding:0 24px 80px; }}
  header.mast {{ border-bottom:3px solid var(--ink); padding:34px 0 16px; margin-bottom:8px; }}
  .mast-title {{ font-family:Georgia,"Iowan Old Style","Times New Roman",serif;
    font-size:54px; line-height:1; letter-spacing:-1px; margin:0; }}
  .mast-title .accent {{ color:var(--anchor); }}
  .mast-sub {{ color:var(--muted); margin:10px 0 0; font-size:15px;
    display:flex; gap:14px; flex-wrap:wrap; align-items:center; }}
  .mast-sub b {{ color:var(--ink); font-weight:600; }}
  .controls {{ position:sticky; top:0; background:var(--paper); padding:14px 0;
    border-bottom:1px solid var(--rule); z-index:5;
    display:flex; gap:10px; flex-wrap:wrap; align-items:center; }}
  .pill {{ font:inherit; font-size:13.5px; border:1px solid var(--ink); background:transparent;
    color:var(--ink); padding:6px 12px; border-radius:999px; cursor:pointer; }}
  .pill.active {{ background:var(--ink); color:var(--paper); }}
  .pill .pc {{ opacity:.6; font-variant-numeric:tabular-nums; margin-left:4px; }}
  #q {{ font:inherit; flex:1; min-width:180px; padding:7px 12px; border:1px solid var(--rule);
    border-radius:8px; background:var(--card); color:var(--ink); }}
  .whatsnew {{ background:var(--anchor-soft); border:1px solid var(--anchor);
    border-radius:12px; padding:16px 20px; margin:22px 0; }}
  .whatsnew h2 {{ margin:0 0 8px; font-size:14px; text-transform:uppercase; letter-spacing:1px;
    color:var(--anchor); }}
  .whatsnew ol {{ margin:0; padding-left:20px; }}
  .whatsnew li {{ margin:5px 0; }}
  .whatsnew a {{ color:var(--ink); text-decoration:none; font-weight:600; }}
  .whatsnew a:hover {{ text-decoration:underline; }}
  .new-src {{ color:var(--muted); font-weight:400; font-size:12.5px; }}
  .topic {{ margin:34px 0 0; }}
  .topic-h {{ font-family:Georgia,serif; font-size:26px; margin:0 0 14px;
    padding-bottom:6px; border-bottom:1px solid var(--rule); }}
  .topic-h .count {{ font-size:14px; color:var(--muted); font-family:inherit;
    vertical-align:middle; }}
  .cluster {{ margin:0 0 14px; }}
  .item {{ background:var(--card); border:1px solid var(--rule); border-radius:10px;
    padding:14px 16px; margin:0 0 10px; }}
  .item-head {{ display:flex; align-items:baseline; gap:8px; flex-wrap:wrap; }}
  .title {{ color:var(--ink); text-decoration:none; font-size:18px; font-weight:600;
    font-family:Georgia,serif; }}
  .title:hover {{ color:var(--link); text-decoration:underline; }}
  .badge {{ background:var(--anchor); color:#fff; font-size:10.5px; font-weight:700;
    letter-spacing:.6px; padding:2px 7px; border-radius:4px; }}
  .pin {{ color:var(--anchor); }}
  .meta {{ color:var(--muted); font-size:12.5px; margin-top:3px; }}
  .meta .dot {{ margin:0 6px; }}
  .summary {{ margin:8px 0 0; color:#3a352d; font-size:15px; }}
  .also-wrap {{ margin:2px 0 0 2px; }}
  .also-wrap summary {{ cursor:pointer; color:var(--link); font-size:13px; }}
  .also-list {{ margin:8px 0 4px; padding-left:18px; }}
  .also-list li {{ margin:3px 0; font-size:14px; }}
  .also-list a {{ color:var(--ink); }}
  .also-src {{ color:var(--muted); font-size:12px; }}
  .empty {{ color:var(--muted); font-style:italic; }}
  .references {{ margin:46px 0 0; border-top:3px solid var(--ink); padding-top:18px; }}
  .references h2 {{ font-family:Georgia,serif; font-size:22px; margin:0 0 4px; }}
  .ref-lead {{ color:var(--muted); font-size:14px; margin:0 0 12px; }}
  .ref-list {{ columns:2; column-gap:28px; padding-left:18px; }}
  .ref-list li {{ margin:0 0 7px; }}
  .ref-note {{ color:var(--muted); font-size:13px; }}
  a {{ color:var(--link); }}
  footer.foot {{ margin-top:40px; color:var(--muted); font-size:12.5px;
    border-top:1px solid var(--rule); padding-top:14px; }}
  @media (max-width:680px) {{ .ref-list {{ columns:1; }} .mast-title {{ font-size:40px; }} }}
  html[data-theme="dark"] {{
    --paper:{PALETTE_DARK['paper']}; --card:{PALETTE_DARK['card']}; --ink:{PALETTE_DARK['ink']};
    --muted:{PALETTE_DARK['muted']}; --rule:{PALETTE_DARK['rule']}; --anchor:{PALETTE_DARK['anchor']};
    --anchor-soft:{PALETTE_DARK['anchor_soft']}; --link:{PALETTE_DARK['link']};
  }}
  html[data-theme="dark"] .summary {{ color:#c8bfb0; }}
  #theme-btn {{ font:inherit; font-size:13px; border:1px solid var(--rule); background:transparent;
    color:var(--muted); padding:5px 11px; border-radius:999px; cursor:pointer; margin-left:auto;
    transition:border-color .15s,color .15s; }}
  #theme-btn:hover {{ border-color:var(--ink); color:var(--ink); }}
</style>
</head>
<body>
<div class="wrap">
  <header class="mast">
    <h1 class="mast-title">The <span class="accent">Daily</span> Brief</h1>
    <p class="mast-sub"><b>{stamp}</b><span>·</span><span>{len(items)} items live</span>
      <span>·</span><span>{new_count} new</span>
      <span>·</span><span>AI · Design · AI×Design/Eng · Tech</span></p>
  </header>

  <div class="controls">
    <button class="pill active" data-filter="all">All</button>
    {pills}
    <input id="q" type="search" placeholder="Filter by keyword…" autocomplete="off">
    <button id="theme-btn" title="Toggle dark mode">Dark</button>
  </div>

  {whats_new}
  {''.join(sections)}
  {refs_html}

  <footer class="foot">
    Generated by <code>/news-digest</code> on {run_date.isoformat()}. Persistent corpus:
    <code>corpus.json</code> · Sources: <code>sources.json</code>. Items age out on a per-topic
    retention window; pinned (★) items stay.
  </footer>
</div>
<script>
  const pills = document.querySelectorAll('.pill');
  const topics = document.querySelectorAll('.topic');
  const q = document.getElementById('q');
  let active = 'all';
  function apply() {{
    const term = q.value.trim().toLowerCase();
    topics.forEach(sec => {{
      const t = sec.dataset.topic;
      const topicMatch = (active === 'all' || active === t);
      let anyVisible = false;
      sec.querySelectorAll('.cluster').forEach(cl => {{
        const blob = cl.querySelector('[data-search]')?.dataset.search || '';
        const hit = !term || blob.includes(term)
          || [...cl.querySelectorAll('[data-search]')].some(n => n.dataset.search.includes(term));
        const show = topicMatch && hit;
        cl.style.display = show ? '' : 'none';
        if (show) anyVisible = true;
      }});
      sec.style.display = topicMatch ? '' : 'none';
      const empty = sec.querySelector('.empty');
      if (empty) empty.style.display = topicMatch ? '' : 'none';
    }});
  }}
  pills.forEach(p => p.addEventListener('click', () => {{
    pills.forEach(x => x.classList.remove('active'));
    p.classList.add('active');
    active = p.dataset.filter;
    apply();
  }}));
  q.addEventListener('input', apply);
  const themeBtn = document.getElementById('theme-btn');
  (function(){{
    const saved = localStorage.getItem('digest-theme');
    if (saved === 'dark') {{ document.documentElement.dataset.theme = 'dark'; themeBtn.textContent = 'Light'; }}
  }})();
  themeBtn.addEventListener('click', () => {{
    const dark = document.documentElement.dataset.theme !== 'dark';
    document.documentElement.dataset.theme = dark ? 'dark' : '';
    themeBtn.textContent = dark ? 'Light' : 'Dark';
    localStorage.setItem('digest-theme', dark ? 'dark' : '');
  }});
</script>
</body>
</html>"""


# --------------------------------------------------------------------------- markdown

def build_markdown(corpus, run_date):
    items = corpus.get("items", [])
    by_topic = defaultdict(list)
    for it in items:
        by_topic[it.get("topic", "tech")].append(it)
    lines = [f"# News Digest — {run_date.isoformat()}", ""]
    new_items = [it for it in items if it.get("is_new")]
    lines.append(f"_{len(items)} items live · {len(new_items)} new since last run._")
    lines.append("")
    if new_items:
        lines.append("## New since last digest")
        for it in sorted(new_items, key=score, reverse=True)[:10]:
            lines.append(f"- [{it.get('title','')}]({it.get('url','#')}) "
                         f"— {it.get('source','')} ({TOPIC_LABELS.get(it.get('topic','tech'),'')})")
        lines.append("")
    for t in TOPICS:
        group = by_topic.get(t, [])
        if not group:
            continue
        lines.append(f"## {TOPIC_LABELS[t]} ({len(group)})")
        for c in cluster_items(group):
            lead = c["lead"]
            tag = " **NEW**" if lead.get("is_new") else ""
            pin = " ★" if lead.get("pinned") else ""
            lines.append(f"- [{lead.get('title','')}]({lead.get('url','#')}) "
                         f"— {lead.get('source','')}{tag}{pin}")
            if lead.get("summary"):
                lines.append(f"  - {lead['summary']}")
            for m in c["members"][1:]:
                lines.append(f"  - also: [{m.get('title','')}]({m.get('url','#')}) — {m.get('source','')}")
        lines.append("")
    lines.append("---")
    lines.append(f"Generated by `/news-digest`. Open `digest.html` for the interactive view.")
    return "\n".join(lines)


# ------------------------------------------------------------------------------- main

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", default=os.path.dirname(os.path.abspath(__file__)))
    args = ap.parse_args()
    root = args.root

    corpus_path = os.path.join(root, "corpus.json")
    sources_path = os.path.join(root, "sources.json")
    corpus = load_json(corpus_path, {"items": [], "references": []})
    sources = load_json(sources_path, {})
    retention_cfg = sources.get("retention_days", corpus.get("retention_days",
                    {"default": 14, "design": 21, "ai_in_design": 30, "evergreen": 90}))

    run_date = today()
    last_run = parse_date(corpus.get("last_run"), run_date)

    # mark new (first_seen since last run) before pruning
    for it in corpus.get("items", []):
        fs = parse_date(it.get("first_seen"), run_date)
        it["is_new"] = fs >= last_run and not it.get("pinned")
        it.setdefault("last_seen", it.get("first_seen", run_date.isoformat()))

    kept, dropped = prune(corpus.get("items", []), retention_cfg, run_date)
    corpus["items"] = kept

    # render
    html_out = build_html(corpus, run_date)
    md_out = build_markdown(corpus, run_date)

    with open(os.path.join(root, "digest.html"), "w", encoding="utf-8") as f:
        f.write(html_out)
    with open(os.path.join(root, "index.html"), "w", encoding="utf-8") as f:
        f.write(html_out)
    with open(os.path.join(root, "Latest Digest.md"), "w", encoding="utf-8") as f:
        f.write(md_out)
    archive_dir = os.path.join(root, "digests")
    os.makedirs(archive_dir, exist_ok=True)
    with open(os.path.join(archive_dir, f"{run_date.isoformat()}.md"), "w", encoding="utf-8") as f:
        f.write(md_out)

    # persist corpus with updated run stamp (drop transient is_new flag from disk copy)
    corpus["last_run"] = run_date.isoformat()
    disk = dict(corpus)
    disk["items"] = [{k: v for k, v in it.items() if k != "is_new"} for it in kept]
    with open(corpus_path, "w", encoding="utf-8") as f:
        json.dump(disk, f, ensure_ascii=False, indent=2)

    print(f"[news-digest] {len(kept)} items kept, {dropped} pruned. "
          f"Wrote digest.html, Latest Digest.md, digests/{run_date.isoformat()}.md")


if __name__ == "__main__":
    main()
