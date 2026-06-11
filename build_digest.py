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


def _age_label(first_seen_date, run_date):
    if not first_seen_date or not run_date:
        return ""
    age = (run_date - first_seen_date).days
    if age <= 0:   return "today"
    if age == 1:   return "yesterday"
    if age < 8:    return f"{age}d ago"
    return f"{first_seen_date.strftime('%b')} {first_seen_date.day}"


def render_item_html(it, lead=True, cluster_key="", run_date=None):
    new_badge = '<span class="badge">NEW</span>' if it.get("is_new") else ""
    src = esc(it.get("source", ""))
    stype = esc(it.get("source_type", ""))
    title = esc(it.get("title", "(untitled)"))
    url = esc(it.get("url", "#"))
    summary = esc(it.get("summary", ""))
    pin = '<span class="pin" title="pinned / evergreen">★</span>' if it.get("pinned") else ""
    cls = "item lead" if lead else "item also"
    rbtl = esc(it.get("rbtl", ""))
    search_blob = esc(" ".join([it.get("title", ""), it.get("summary", ""),
                                it.get("rbtl", ""), it.get("source", ""),
                                " ".join(it.get("topics", []))])).lower()
    summ_html = f'<p class="summary">{summary}</p>' if (summary and lead) else ""
    rbtl_html = (f'<p class="rbtl"><span class="rbtl-label">Reading between the lines</span>'
                 f'{rbtl}</p>') if (rbtl and lead) else ""

    # date stamp
    fs_date = parse_date(it.get("first_seen"))
    age_str = _age_label(fs_date, run_date)
    raw_date = esc(str(it.get("first_seen", ""))[:10])
    date_html = (f'<span class="date-stamp" title="{raw_date}">&nbsp;·&nbsp;{esc(age_str)}</span>'
                 ) if age_str else ""

    # card action buttons and reader trigger (lead cards only)
    if lead and cluster_key:
        k = esc(cluster_key)
        reader_attr = ' data-reader="1"'
        ext_link = f'<a class="ext-link" href="{url}" target="_blank" rel="noopener" data-tip="Open in new tab">↗</a>'
        actions_html = (
            f'<div class="card-actions">'
            f'<button class="card-btn read-btn" data-key="{k}" data-tip="Mark read (m)" aria-label="Mark read"></button>'
            f'<button class="card-btn rl-btn" data-key="{k}" data-tip="Save for later (b)">🔖</button>'
            f'<button class="card-btn snooze-btn" data-key="{k}" data-tip="Snooze until tomorrow (s)">💤</button>'
            f'<button class="card-btn dismiss-btn" data-key="{k}" data-tip="Archive (x)">✓</button>'
            f'</div>'
        )
    else:
        reader_attr = ""
        ext_link = ""
        actions_html = ""

    return f"""<article class="{cls}" data-search="{search_blob}">
  <div class="item-head">
    <div class="item-head-main">
      <a class="title" href="{url}" target="_blank" rel="noopener"{reader_attr}>{title}</a>
      {new_badge}{pin}{ext_link}
    </div>
    {actions_html}
  </div>
  <div class="meta"><span class="src">{src}</span><span class="dot">·</span><span class="stype">{stype}</span>{date_html}</div>
  {summ_html}
  {rbtl_html}
</article>"""


def render_cluster_html(cluster, run_date=None):
    key = cluster["key"]
    key_esc = esc(key)
    lead = cluster["lead"]
    lead_html = render_item_html(lead, lead=True, cluster_key=key, run_date=run_date)
    note_area = f'<div class="note-area" data-key="{key_esc}"></div>'
    extras = cluster["members"][1:]
    also_html = ""
    if extras:
        also = "".join(
            f'<li><a href="{esc(m.get("url","#"))}" target="_blank" rel="noopener">{esc(m.get("title",""))}</a>'
            f' <span class="also-src">{esc(m.get("source",""))}</span></li>'
            for m in extras
        )
        also_html = (
            f'<details class="also-wrap"><summary>+ {len(extras)} more on this story</summary>'
            f'<ul class="also-list">{also}</ul></details>'
        )
    drag_handle = '<div class="drag-handle" data-tip="Drag to reorder">⠿</div>'
    return (f'<div class="cluster" draggable="true" data-key="{key_esc}">'
            f'{drag_handle}{lead_html}{note_area}{also_html}</div>')


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
        cluster_count = len(clusters)
        counts[t] = sum(len(c["members"]) for c in clusters)
        if not clusters:
            body = '<p class="empty">Nothing new in this lane right now.</p>'
        else:
            body = "".join(render_cluster_html(c, run_date=run_date) for c in clusters)
        topic_ring_html = (
            f'<span class="topic-progress" data-topic="{t}" title="Read progress">'
            f'<svg class="topic-ring" viewBox="0 0 24 24" aria-hidden="true">'
            f'<circle class="ring-bg" cx="12" cy="12" r="9"/>'
            f'<circle class="ring-fg" cx="12" cy="12" r="9"/></svg>'
            f'<span class="topic-ring-label">0/{cluster_count}</span>'
            f'</span>'
        )
        sections.append(
            f'<section class="topic" data-topic="{t}">'
            f'<h2 class="topic-h">{esc(TOPIC_LABELS[t])} '
            f'<span class="count">{counts[t]}</span>'
            f'{topic_ring_html}</h2>{body}</section>'
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

    # daily insight — top-scored new item with an rbtl
    top_rbtl = sorted([it for it in items if it.get("is_new") and it.get("rbtl")],
                      key=score, reverse=True)
    if top_rbtl:
        ins = top_rbtl[0]
        insight_html = (
            f'<section class="insight-card">'
            f'<div class="insight-label">Today\'s insight</div>'
            f'<blockquote class="insight-quote">{esc(ins.get("rbtl",""))}</blockquote>'
            f'<div class="insight-src"><a href="{esc(ins.get("url","#"))}" target="_blank" rel="noopener">'
            f'{esc(ins.get("title",""))}</a>'
            f'<span class="insight-from"> — {esc(ins.get("source",""))}</span></div>'
            f'</section>'
        )
    else:
        insight_html = ""

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
<link rel="icon" href="data:image/svg+xml,<svg viewBox='0 0 44 44' fill='none' xmlns='http://www.w3.org/2000/svg'><rect x='3' y='6' width='29' height='32' rx='5' stroke='%23c8482b' stroke-width='2.5'/><line x1='10' y1='15' x2='26' y2='15' stroke='%23c8482b' stroke-width='2.5' stroke-linecap='round'/><line x1='10' y1='21' x2='26' y2='21' stroke='%23c8482b' stroke-width='2.5' stroke-linecap='round'/><line x1='10' y1='27' x2='20' y2='27' stroke='%23c8482b' stroke-width='2.5' stroke-linecap='round'/><circle cx='36' cy='11' r='7' fill='%23c8482b'/><circle cx='36' cy='11' r='3.5' fill='white' opacity='.9'/></svg>" type="image/svg+xml">
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
  .controls {{ position:sticky; top:0; background:var(--paper); padding:10px 0;
    border-bottom:1px solid var(--rule); z-index:5;
    display:flex; flex-wrap:wrap; gap:8px; align-items:center; }}
  .pills-row {{ display:flex; flex-wrap:wrap; gap:7px; align-items:center; flex:1; min-width:0; }}
  .pill {{ font:inherit; font-size:13.5px; border:1px solid var(--ink); background:transparent;
    color:var(--ink); padding:6px 12px; border-radius:999px; cursor:pointer;
    touch-action:manipulation; }}
  .pill.active {{ background:var(--ink); color:var(--paper); }}
  .pill .pc {{ opacity:.6; font-variant-numeric:tabular-nums; margin-left:4px; }}
  .search-row {{ display:flex; gap:8px; align-items:center; flex-shrink:0; }}
  #q {{ font:inherit; flex:1; min-width:160px; padding:7px 12px; border:1px solid var(--rule);
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
  .item-head {{ display:flex; align-items:flex-start; gap:8px; flex-wrap:nowrap; }}
  .item-head-main {{ flex:1; min-width:0; display:flex; align-items:baseline; gap:8px; flex-wrap:wrap; }}
  .title {{ color:var(--ink); text-decoration:none; font-size:18px; font-weight:600;
    font-family:Georgia,serif; }}
  .title[data-reader] {{ cursor:pointer; }}
  .title:hover {{ color:var(--link); text-decoration:underline; }}
  .ext-link {{ color:var(--muted); font-size:12px; text-decoration:none; opacity:.55;
    margin-left:5px; flex-shrink:0; vertical-align:middle; transition:opacity .12s; }}
  .ext-link:hover {{ opacity:1; color:var(--link); }}
  .badge {{ background:var(--anchor); color:#fff; font-size:10.5px; font-weight:700;
    letter-spacing:.6px; padding:2px 7px; border-radius:4px; }}
  .pin {{ color:var(--anchor); }}
  .meta {{ color:var(--muted); font-size:12.5px; margin-top:3px; }}
  .meta .dot {{ margin:0 6px; }}
  .summary {{ margin:8px 0 0; color:#3a352d; font-size:15px; }}
  .rbtl {{ margin:8px 0 0; font-size:14px; color:var(--muted); font-style:italic; line-height:1.5; }}
  .rbtl-label {{ font-style:normal; font-size:10.5px; font-weight:700; text-transform:uppercase;
    letter-spacing:.7px; display:block; color:var(--anchor); opacity:.85; margin-bottom:3px; }}
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
  @media (max-width:680px) {{ .mast-title {{ font-size:38px; }} .ref-list {{ columns:1; }} }}
  @media (max-width:600px) {{
    .wrap {{ padding:0 16px 60px; }}
    .mast-title {{ font-size:28px; letter-spacing:-.3px; }}
    .mast-sub {{ font-size:13px; gap:6px; }}
    .mast-topics {{ display:none; }}
    .controls {{ flex-direction:column; align-items:stretch; gap:6px; }}
    .pills-row {{ flex-wrap:nowrap; overflow-x:auto; -webkit-overflow-scrolling:touch;
      scrollbar-width:none; gap:6px; padding-bottom:2px; }}
    .pills-row::-webkit-scrollbar {{ display:none; }}
    .pill {{ flex-shrink:0; font-size:12.5px; padding:7px 10px; }}
    .search-row {{ gap:6px; }}
    #q {{ min-width:0; font-size:15px; }}
    #theme-btn {{ padding:7px 11px; }}
    .topic-h {{ font-size:21px; }}
    .title {{ font-size:15px; line-height:1.35; }}
    .item {{ padding:12px 13px; }}
    .summary {{ font-size:14px; }}
    .whatsnew {{ padding:12px 14px; }}
    .card-btn {{ width:32px; height:32px; font-size:14px; }}
    .card-actions {{ gap:5px; margin-left:4px; }}
    .drag-handle {{ opacity:.35; left:-14px; }}
    .topic-ring {{ width:16px; height:16px; }}
    .topic-ring-label {{ font-size:10px; }}
  }}
  @media (hover:none) {{
    .drag-handle {{ opacity:.3; }}
    .cluster:hover .drag-handle {{ opacity:.3; }}
  }}
  /* masthead logo */
  .mast-logo-row {{ display:flex; align-items:center; gap:14px; }}
  .mast-logo {{ width:44px; height:44px; color:var(--ink); flex-shrink:0; }}
  /* card actions + kanban */
  .card-actions {{ display:flex; align-items:center; gap:4px; flex-shrink:0; margin-left:6px; }}
  /* per-card read toggle */
  .read-btn::before {{ content:'○'; }}
  .cluster.is-read .read-btn::before {{ content:'●'; }}
  .cluster.is-read .read-btn {{ color:var(--anchor); border-color:var(--anchor-soft); }}
  .cluster.is-read .item.lead {{ opacity:.65; }}
  .card-btn {{ width:26px; height:26px; border-radius:50%; border:1px solid var(--rule);
    background:transparent; color:var(--muted); font-size:13px; line-height:1; cursor:pointer;
    display:flex; align-items:center; justify-content:center;
    transition:background .15s,border-color .15s,color .15s; padding:0;
    touch-action:manipulation; }}
  .card-btn:hover {{ background:var(--card); border-color:var(--ink); color:var(--ink); }}
  .dismiss-btn:hover {{ background:var(--anchor) !important; border-color:var(--anchor) !important; color:#fff !important; }}
  .snooze-btn.active {{ border-color:#b8960c; color:#b8960c; }}
  .rl-btn.active {{ border-color:var(--link); color:var(--link); }}
  /* topic-level read progress ring */
  .topic-progress {{ display:inline-flex; align-items:center; gap:5px; margin-left:12px;
    vertical-align:middle; opacity:.85; }}
  .topic-ring {{ width:20px; height:20px; flex-shrink:0; }}
  .topic-ring .ring-bg {{ fill:none; stroke:var(--rule); stroke-width:2.5; }}
  .topic-ring .ring-fg {{ fill:none; stroke:var(--anchor); stroke-width:2.5;
    stroke-dasharray:56.55; stroke-dashoffset:56.55;
    transition:stroke-dashoffset .5s ease; transform:rotate(-90deg); transform-origin:center; }}
  .topic-ring-label {{ font-size:11px; color:var(--muted); font-variant-numeric:tabular-nums; }}
  .date-stamp {{ color:var(--muted); font-size:11.5px; }}
  /* drag handle */
  .cluster {{ position:relative; }}
  .drag-handle {{ position:absolute; top:10px; left:-18px; color:var(--muted); font-size:14px;
    cursor:grab; opacity:0; transition:opacity .15s; line-height:1; user-select:none; padding:2px 4px; }}
  .cluster:hover .drag-handle {{ opacity:1; }}
  .cluster[draggable] {{ cursor:default; }}
  .cluster.drag-over {{ outline:2px dashed var(--anchor); outline-offset:4px; border-radius:12px; }}
  .cluster.dragging {{ opacity:.35; pointer-events:none; }}
  /* focus state — left accent bar instead of outline */
  .cluster.focused > .item.lead {{ border-left:3px solid var(--anchor); padding-left:13px;
    background:var(--anchor-soft); transition:background .2s; scroll-margin:90px; }}
  .cluster:hover > .item.lead {{ background:color-mix(in srgb, var(--card) 90%, var(--anchor) 10%); }}
  .cluster.focused:hover > .item.lead {{ background:var(--anchor-soft); }}
  /* tooltips */
  [data-tip] {{ position:relative; }}
  [data-tip]::after {{ content:attr(data-tip); position:absolute; bottom:calc(100% + 7px);
    left:50%; transform:translateX(-50%); background:var(--ink); color:var(--paper);
    font-size:11px; font-family:-apple-system,BlinkMacSystemFont,"Segoe UI",sans-serif;
    font-weight:400; padding:4px 8px; border-radius:5px; white-space:nowrap;
    pointer-events:none; opacity:0; transition:opacity .12s; z-index:20; }}
  [data-tip]:hover::after {{ opacity:1; }}
  .arc-pill {{ font:inherit; font-size:12px; border:1px solid var(--rule); background:transparent;
    color:var(--muted); padding:4px 10px; border-radius:999px; cursor:pointer;
    white-space:nowrap; transition:border-color .15s,color .15s; }}
  .arc-pill:hover {{ border-color:var(--ink); color:var(--ink); }}
  .arc-pill.has-arc {{ border-color:var(--anchor); color:var(--anchor); }}
  #help-btn {{ width:28px; height:28px; padding:0; display:inline-flex; align-items:center;
    justify-content:center; font-size:13px; font-weight:700; }}
  /* note area */
  .note-area {{ padding:2px 6px 4px; }}
  .note-trigger {{ font:inherit; font-size:12px; color:var(--muted); background:transparent;
    border:1px solid var(--rule); border-radius:999px; cursor:pointer;
    padding:3px 10px; display:inline-flex; align-items:center; gap:5px;
    transition:border-color .15s,color .15s,background .15s; user-select:none; margin:2px 0; }}
  .note-trigger:hover {{ border-color:var(--ink); color:var(--ink); }}
  .note-trigger.has-note {{ border-color:var(--link); color:var(--link); }}
  .note-body {{ margin:6px 0 4px; }}
  .note-input {{ width:100%; font:inherit; font-size:13.5px; resize:none;
    border:1px solid var(--rule); border-radius:8px; background:var(--card); color:var(--ink);
    padding:8px 10px; }}
  .note-input:focus {{ outline:2px solid var(--anchor); border-color:transparent; }}
  .note-display {{ font-size:13.5px; color:var(--muted); white-space:pre-wrap;
    padding:4px 4px 6px; font-style:italic; display:none; border-left:2px solid var(--rule);
    margin-left:2px; padding-left:10px; }}
  .note-display.visible {{ display:block; }}
  /* insight card */
  .insight-card {{ margin:22px 0 10px; padding:18px 22px 16px; border-radius:12px;
    background:linear-gradient(135deg,var(--anchor-soft) 0%,var(--card) 100%);
    border:1px solid var(--anchor); }}
  .insight-label {{ font-size:10.5px; font-weight:700; text-transform:uppercase; letter-spacing:.8px;
    color:var(--anchor); margin-bottom:8px; }}
  .insight-quote {{ margin:0 0 10px; font-family:Georgia,serif; font-size:16px; line-height:1.6;
    color:var(--ink); font-style:italic; }}
  .insight-src {{ font-size:13px; color:var(--muted); }}
  .insight-src a {{ color:var(--ink); font-weight:600; text-decoration:none; }}
  .insight-src a:hover {{ text-decoration:underline; }}
  .insight-from {{ color:var(--muted); }}
  html[data-theme="dark"] {{
    --paper:{PALETTE_DARK['paper']}; --card:{PALETTE_DARK['card']}; --ink:{PALETTE_DARK['ink']};
    --muted:{PALETTE_DARK['muted']}; --rule:{PALETTE_DARK['rule']}; --anchor:{PALETTE_DARK['anchor']};
    --anchor-soft:{PALETTE_DARK['anchor_soft']}; --link:{PALETTE_DARK['link']};
  }}
  html[data-theme="dark"] .summary {{ color:#c8bfb0; }}
  #theme-btn {{ font:inherit; font-size:13px; border:1px solid var(--rule); background:transparent;
    color:var(--muted); padding:5px 11px; border-radius:999px; cursor:pointer;
    transition:border-color .15s,color .15s; touch-action:manipulation; white-space:nowrap; }}
  #theme-btn:hover {{ border-color:var(--ink); color:var(--ink); }}
  /* ── reading pane ──────────────────────────────────────────────────────── */
  .reading-pane {{ display:none; position:fixed; top:0; right:0; width:44vw; height:100vh;
    background:var(--card); border-left:2px solid var(--rule); z-index:50;
    flex-direction:column; box-shadow:-6px 0 32px rgba(0,0,0,.10); }}
  .reading-pane.open {{ display:flex; }}
  body.pane-open .wrap {{ padding-right:calc(44vw + 8px); }}
  .pane-toolbar {{ display:flex; align-items:center; padding:10px 14px; border-bottom:1px solid var(--rule);
    gap:8px; flex-shrink:0; position:sticky; top:0; background:var(--card); z-index:2; }}
  .pane-site {{ font-size:11.5px; color:var(--muted); font-family:monospace; }}
  .pane-close,.pane-newtab {{ width:28px; height:28px; border-radius:50%; border:1px solid var(--rule);
    background:transparent; color:var(--muted); font-size:16px; cursor:pointer; display:flex;
    align-items:center; justify-content:center;
    transition:border-color .15s,color .15s; text-decoration:none; flex-shrink:0; }}
  .pane-close:hover,.pane-newtab:hover {{ border-color:var(--ink); color:var(--ink); }}
  .pane-body {{ flex:1; overflow-y:auto; padding:22px 26px 60px; }}
  .pane-loading {{ color:var(--muted); font-style:italic; padding:24px 0; animation:pulse 1.4s ease infinite; }}
  @keyframes pulse {{ 0%,100% {{ opacity:.5; }} 50% {{ opacity:1; }} }}
  .pane-error {{ color:var(--anchor); font-size:14px; padding:8px 0 4px; line-height:1.5; }}
  .pane-error a {{ color:var(--link); }}
  .pane-title {{ font-family:Georgia,serif; font-size:21px; font-weight:700; line-height:1.3;
    margin:0 0 8px; color:var(--ink); }}
  .pane-byline {{ font-size:12px; color:var(--muted); margin-bottom:16px; padding-bottom:14px;
    border-bottom:1px solid var(--rule); }}
  .pane-content {{ font-size:15.5px; line-height:1.75; color:var(--ink); }}
  .pane-content p {{ margin:0 0 1em; }}
  .pane-content h1,.pane-content h2,.pane-content h3,.pane-content h4 {{
    font-family:Georgia,serif; margin:1.4em 0 .5em; line-height:1.25; }}
  .pane-content h1 {{ font-size:1.4em; }} .pane-content h2 {{ font-size:1.2em; }}
  .pane-content h3 {{ font-size:1.05em; }}
  .pane-content a {{ color:var(--link); }}
  .pane-content img {{ max-width:100%; height:auto; border-radius:6px; margin:8px 0; display:block; }}
  .pane-content figure {{ margin:1em 0; }}
  .pane-content figcaption {{ font-size:13px; color:var(--muted); margin-top:4px; }}
  .pane-content blockquote {{ border-left:3px solid var(--anchor); margin:1em 0;
    padding-left:14px; color:var(--muted); font-style:italic; }}
  .pane-content pre {{ background:var(--paper); border-radius:6px; padding:14px; overflow-x:auto;
    font-size:13px; border:1px solid var(--rule); }}
  .pane-content code {{ background:var(--paper); border-radius:3px; padding:1px 5px;
    font-size:.88em; }}
  .pane-content pre code {{ background:none; padding:0; }}
  .pane-content ul,.pane-content ol {{ padding-left:22px; margin:0 0 1em; }}
  .pane-content li {{ margin:.3em 0; }}
  .pane-content mark.hl {{ background:#fff176; color:inherit; border-radius:2px; padding:0 1px; }}
  html[data-theme="dark"] .pane-content mark.hl {{ background:#4a3d00; }}
  /* highlight tooltip */
  .hl-tooltip {{ position:fixed; background:var(--ink); color:var(--paper); border-radius:7px;
    padding:3px 4px; z-index:200; box-shadow:0 2px 8px rgba(0,0,0,.2); }}
  #hl-btn {{ background:none; border:none; color:var(--paper); cursor:pointer;
    font-size:12px; padding:3px 8px; white-space:nowrap; font-family:inherit; }}
  #hl-btn:hover {{ opacity:.8; }}
  @media (max-width:900px) {{
    .reading-pane {{ width:100vw; border-left:none; }}
    body.pane-open .wrap {{ padding-right:0; }}
  }}
</style>
</head>
<body>
<div class="wrap">
  <header class="mast">
    <div class="mast-logo-row">
      <svg class="mast-logo" viewBox="0 0 44 44" fill="none" xmlns="http://www.w3.org/2000/svg" aria-hidden="true">
        <rect x="3" y="6" width="29" height="32" rx="5" stroke="currentColor" stroke-width="2.5"/>
        <line x1="10" y1="15" x2="26" y2="15" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"/>
        <line x1="10" y1="21" x2="26" y2="21" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"/>
        <line x1="10" y1="27" x2="20" y2="27" stroke="currentColor" stroke-width="2.5" stroke-linecap="round"/>
        <circle cx="36" cy="11" r="7" fill="var(--anchor)"/>
        <circle cx="36" cy="11" r="3.5" fill="white" opacity=".9"/>
      </svg>
      <h1 class="mast-title">The <span class="accent">Daily</span> Brief</h1>
    </div>
    <p class="mast-sub"><b>{stamp}</b><span>·</span><span>{len(items)} items live</span>
      <span>·</span><span>{new_count} new</span>
      <span>·</span><span class="mast-topics">AI · Design · AI×Design/Eng · Tech</span></p>
  </header>

  <div class="controls">
    <div class="pills-row">
      <button class="pill active" data-filter="all">All</button>
      {pills}
    </div>
    <div class="search-row">
      <input id="q" type="search" placeholder="Filter… (/ to focus)" autocomplete="off">
      <button id="rl-pill" class="arc-pill">Saved</button>
      <button id="arc-pill" class="arc-pill">Archive</button>
      <button id="theme-btn" title="Toggle dark mode">Dark</button>
      <button id="help-btn" class="arc-pill" data-tip="Keyboard shortcuts" aria-label="Help">?</button>
    </div>
  </div>

  {insight_html}
  {whats_new}
  {''.join(sections)}
  {refs_html}

  <footer class="foot">
    Generated by <code>/news-digest</code> on {run_date.isoformat()}. Persistent corpus:
    <code>corpus.json</code> · Sources: <code>sources.json</code>. Items age out on a per-topic
    retention window; pinned (★) items stay.
  </footer>
</div>

<div id="reading-pane" class="reading-pane" role="complementary" aria-label="Article reader">
  <div class="pane-toolbar">
    <span class="pane-site"></span>
    <div style="flex:1"></div>
    <a class="pane-newtab" target="_blank" rel="noopener" href="#" data-tip="Open in new tab">↗</a>
    <button class="pane-close" data-tip="Close (Esc)" aria-label="Close reader">×</button>
  </div>
  <div class="pane-body">
    <div class="pane-loading">Loading…</div>
    <div class="pane-error" style="display:none"></div>
    <h1 class="pane-title"></h1>
    <div class="pane-byline"></div>
    <div class="pane-content"></div>
  </div>
  <div class="hl-tooltip" id="hl-tooltip" style="display:none">
    <button id="hl-btn">✦ Highlight</button>
  </div>
</div>
<script>
  // ── helpers ──────────────────────────────────────────────────────────────
  function ls(k) {{ return localStorage.getItem(k); }}
  function lsSet(k, v) {{ localStorage.setItem(k, JSON.stringify(v)); }}
  function setOf(k) {{ try {{ return new Set(JSON.parse(ls(k) || '[]')); }} catch(e) {{ return new Set(); }} }}
  function objOf(k) {{ try {{ return JSON.parse(ls(k) || '{{}}'); }} catch(e) {{ return {{}}; }} }}
  function esc2(s) {{ return CSS.escape(String(s)); }}

  // ── state ─────────────────────────────────────────────────────────────────
  const pills    = document.querySelectorAll('.pill');
  const topicSec = document.querySelectorAll('.topic');
  const q        = document.getElementById('q');
  const arcPill  = document.getElementById('arc-pill');
  const rlPill   = document.getElementById('rl-pill');
  const themeBtn = document.getElementById('theme-btn');
  const todayStr = new Date().toISOString().split('T')[0];

  let active   = 'all';
  let viewMode = 'normal';  // 'normal' | 'archive' | 'readlater'

  let archived  = setOf('digest-archived');
  let readSet   = setOf('digest-read');
  let readLater = setOf('digest-readlater');
  let snoozed   = objOf('digest-snoozed');
  let notes     = objOf('digest-notes');

  // expire past snoozes on load
  Object.keys(snoozed).forEach(k => {{ if (snoozed[k] <= todayStr) delete snoozed[k]; }});
  lsSet('digest-snoozed', snoozed);

  // ── cluster class sync ────────────────────────────────────────────────────
  function syncClasses() {{
    document.querySelectorAll('.cluster[data-key]').forEach(cl => {{
      const k = cl.dataset.key;
      cl.classList.toggle('is-read', readSet.has(k));
      const rlBtn  = cl.querySelector('.rl-btn');
      const snzBtn = cl.querySelector('.snooze-btn');
      if (rlBtn)  rlBtn.classList.toggle('active', readLater.has(k));
      if (snzBtn) snzBtn.classList.toggle('active', !!snoozed[k]);
    }});
  }}
  syncClasses();
  updateTopicRings();

  // ── notes ─────────────────────────────────────────────────────────────────
  function buildNotes() {{
    document.querySelectorAll('.note-area[data-key]').forEach(area => {{
      if (area.dataset.built) return;
      area.dataset.built = '1';
      const k = area.dataset.key;

      const trigger = document.createElement('button');
      trigger.className = 'note-trigger';
      const body    = document.createElement('div');
      body.className = 'note-body';
      body.style.display = 'none';
      const ta      = document.createElement('textarea');
      ta.className  = 'note-input';
      ta.rows       = 3;
      ta.placeholder = 'Your thoughts…';
      if (notes[k]) ta.value = notes[k];
      const display = document.createElement('div');
      display.className = 'note-display' + (notes[k] ? ' visible' : '');
      display.textContent = notes[k] || '';

      function refresh() {{
        const saved = notes[k] || '';
        display.textContent = saved;
        display.classList.toggle('visible', !!saved);
        trigger.classList.toggle('has-note', !!saved);
        trigger.textContent = saved ? '✏️ Edit note' : '✏️ Add note';
      }}
      refresh();

      ta.addEventListener('input', () => {{
        const v = ta.value.trim();
        if (v) notes[k] = v; else delete notes[k];
        lsSet('digest-notes', notes);
        refresh();
      }});
      ta.addEventListener('keydown', e => {{ if (e.key === 'Escape') {{ body.style.display = 'none'; refresh(); }} }});

      trigger.addEventListener('click', () => {{
        const open = body.style.display === 'none';
        body.style.display = open ? '' : 'none';
        if (open) {{ ta.focus(); trigger.textContent = '✏️ Cancel'; }}
        else refresh();
      }});

      body.appendChild(ta);
      area.appendChild(trigger);
      area.appendChild(display);
      area.appendChild(body);
    }});
  }}
  buildNotes();

  // ── pill counters ─────────────────────────────────────────────────────────
  function updatePills() {{
    const rlN  = readLater.size;
    const arcN = archived.size;
    rlPill.textContent  = viewMode === 'readlater'
      ? (rlN ? 'Saved (' + rlN + ') \xd7' : 'Saved \xd7')
      : (rlN ? 'Saved (' + rlN + ')' : 'Saved');
    arcPill.textContent = viewMode === 'archive'
      ? (arcN ? 'Archive (' + arcN + ') \xd7' : 'Archive \xd7')
      : (arcN ? 'Archive (' + arcN + ')' : 'Archive');
    rlPill.classList.toggle('has-arc',  rlN > 0  || viewMode === 'readlater');
    arcPill.classList.toggle('has-arc', arcN > 0 || viewMode === 'archive');
  }}

  // ── topic read-progress rings ─────────────────────────────────────────────
  function updateTopicRings() {{
    document.querySelectorAll('.topic[data-topic]').forEach(sec => {{
      const prog = sec.querySelector('.topic-progress');
      if (!prog) return;
      const all = [...sec.querySelectorAll('.cluster[data-key]')];
      const visible = all.filter(c => c.style.display !== 'none');
      const total = visible.length;
      const read  = visible.filter(c => readSet.has(c.dataset.key)).length;
      const fg  = prog.querySelector('.ring-fg');
      const lbl = prog.querySelector('.topic-ring-label');
      if (fg) fg.style.strokeDashoffset = total ? String(56.55 * (1 - read / total)) : '56.55';
      if (lbl) lbl.textContent = read + '/' + total;
    }});
  }}

  // ── filter / apply ────────────────────────────────────────────────────────
  function isVisible(k) {{
    if (viewMode === 'archive')   return archived.has(k);
    if (viewMode === 'readlater') return readLater.has(k) && !archived.has(k);
    return !archived.has(k) && !snoozed[k];
  }}

  function apply() {{
    const term = q.value.trim().toLowerCase();
    topicSec.forEach(sec => {{
      const topicMatch = (active === 'all' || active === sec.dataset.topic);
      sec.querySelectorAll('.cluster').forEach(cl => {{
        const k = cl.dataset.key;
        const vis = isVisible(k);
        const blob = cl.querySelector('[data-search]')?.dataset.search || '';
        const hit = !term || blob.includes(term)
          || [...cl.querySelectorAll('[data-search]')].some(n => n.dataset.search.includes(term));
        cl.style.display = (topicMatch && hit && vis) ? '' : 'none';
      }});
      sec.style.display = topicMatch ? '' : 'none';
      const empty = sec.querySelector('.empty');
      if (empty) empty.style.display = topicMatch ? '' : 'none';
    }});
    updatePills();
    updateTopicRings();
  }}
  apply();

  pills.forEach(p => p.addEventListener('click', () => {{
    pills.forEach(x => x.classList.remove('active'));
    p.classList.add('active');
    active = p.dataset.filter;
    apply();
  }}));
  q.addEventListener('input', apply);

  rlPill.addEventListener('click',  () => {{ viewMode = viewMode === 'readlater' ? 'normal' : 'readlater'; apply(); }});
  arcPill.addEventListener('click', () => {{ viewMode = viewMode === 'archive'   ? 'normal' : 'archive';   apply(); }});

  // ── actions ───────────────────────────────────────────────────────────────
  function doArchive(key) {{
    archived.add(key); lsSet('digest-archived', [...archived]);
    if (focusedKey === key) moveFocus(1);
    apply();
  }}
  function doSnooze(key) {{
    if (snoozed[key]) {{ delete snoozed[key]; }}
    else {{
      const d = new Date(); d.setDate(d.getDate() + 1);
      snoozed[key] = d.toISOString().split('T')[0];
    }}
    lsSet('digest-snoozed', snoozed);
    syncClasses();
    if (snoozed[key]) {{ if (focusedKey === key) moveFocus(1); apply(); }}
    else apply();
  }}
  function doRL(key) {{
    if (readLater.has(key)) readLater.delete(key); else readLater.add(key);
    lsSet('digest-readlater', [...readLater]);
    syncClasses(); apply();
  }}
  function doRead(key) {{
    if (readSet.has(key)) readSet.delete(key); else readSet.add(key);
    lsSet('digest-read', [...readSet]);
    syncClasses();
    updateTopicRings();
  }}

  // button click delegation
  document.addEventListener('click', e => {{
    if (e.target.closest('.dismiss-btn')) {{
      const k = e.target.closest('[data-key]').dataset.key; e.stopPropagation(); doArchive(k); return;
    }}
    if (e.target.closest('.snooze-btn')) {{
      const k = e.target.closest('[data-key]').dataset.key; e.stopPropagation(); doSnooze(k); return;
    }}
    if (e.target.closest('.rl-btn')) {{
      const k = e.target.closest('[data-key]').dataset.key; e.stopPropagation(); doRL(k); return;
    }}
    if (e.target.closest('.read-btn')) {{
      const k = e.target.closest('[data-key]').dataset.key; e.stopPropagation(); doRead(k); return;
    }}
  }});

  // title click → open reader pane (lead cards only)
  document.addEventListener('click', e => {{
    const link = e.target.closest('.title[data-reader]');
    if (!link) return;
    e.preventDefault();
    e.stopPropagation();
    const cl = link.closest('.cluster[data-key]');
    if (cl) doRead(cl.dataset.key);
    openInPane(link.href, link.textContent.trim());
  }});

  // ring keyboard
  document.addEventListener('keydown', e => {{
    if ((e.key === 'Enter' || e.key === ' ') && e.target.classList.contains('read-btn')) {{
      e.preventDefault();
      doRead(e.target.dataset.key);
    }}
  }});

  // ── help button ───────────────────────────────────────────────────────────
  document.getElementById('help-btn').addEventListener('click', showShortcuts);

  // ── drag to reorder ───────────────────────────────────────────────────────
  let dragSrc = null;
  document.addEventListener('dragstart', e => {{
    if (!e.target.closest('.drag-handle')) {{ e.preventDefault(); return; }}
    const cl = e.target.closest('.cluster[draggable]');
    if (!cl) return;
    dragSrc = cl; cl.classList.add('dragging');
    e.dataTransfer.effectAllowed = 'move';
  }});
  document.addEventListener('dragend', () => {{
    document.querySelectorAll('.cluster').forEach(c => c.classList.remove('dragging','drag-over'));
    saveDragOrder(); dragSrc = null;
  }});
  document.addEventListener('dragover', e => {{
    e.preventDefault(); e.dataTransfer.dropEffect = 'move';
    const cl = e.target.closest('.cluster[draggable]');
    document.querySelectorAll('.cluster').forEach(c => c.classList.remove('drag-over'));
    if (cl && cl !== dragSrc) cl.classList.add('drag-over');
  }});
  document.addEventListener('drop', e => {{
    e.preventDefault();
    const target = e.target.closest('.cluster[draggable]');
    if (!target || !dragSrc || target === dragSrc || target.parentNode !== dragSrc.parentNode) return;
    const all = [...target.parentNode.querySelectorAll(':scope > .cluster[draggable]')];
    const si = all.indexOf(dragSrc), ti = all.indexOf(target);
    if (si < ti) target.parentNode.insertBefore(dragSrc, target.nextSibling);
    else target.parentNode.insertBefore(dragSrc, target);
  }});
  function saveDragOrder() {{
    const orders = {{}};
    topicSec.forEach(sec => {{
      orders[sec.dataset.topic] = [...sec.querySelectorAll(':scope > .cluster[data-key]')].map(c => c.dataset.key);
    }});
    lsSet('digest-order', orders);
  }}
  (function restoreDragOrder() {{
    const saved = objOf('digest-order');
    topicSec.forEach(sec => {{
      const order = saved[sec.dataset.topic];
      if (!order || !order.length) return;
      order.forEach(key => {{
        const el = sec.querySelector(':scope > .cluster[data-key="' + esc2(key) + '"]');
        if (el) sec.appendChild(el);
      }});
    }});
  }})();

  // ── keyboard navigation ───────────────────────────────────────────────────
  let focusedKey = null;

  function visibleClusters() {{
    return [...document.querySelectorAll('.cluster[data-key]')].filter(c => c.style.display !== 'none');
  }}
  function moveFocus(delta) {{
    const list = visibleClusters();
    if (!list.length) return;
    let idx = focusedKey ? list.findIndex(c => c.dataset.key === focusedKey) : -1;
    if (idx === -1) idx = delta > 0 ? -1 : 0;
    idx = Math.max(0, Math.min(list.length - 1, idx + delta));
    setFocus(list[idx]);
  }}
  function setFocus(cl) {{
    document.querySelectorAll('.cluster.focused').forEach(c => c.classList.remove('focused'));
    if (!cl) {{ focusedKey = null; return; }}
    cl.classList.add('focused');
    focusedKey = cl.dataset.key;
    cl.scrollIntoView({{ block: 'nearest', behavior: 'smooth' }});
  }}

  document.addEventListener('keydown', e => {{
    const inField = e.target.tagName === 'INPUT' || e.target.tagName === 'TEXTAREA';
    if (inField) {{ if (e.key === 'Escape') e.target.blur(); return; }}
    switch (e.key) {{
      case 'ArrowDown': case 'j': e.preventDefault(); moveFocus(1);  break;
      case 'ArrowUp':   case 'k': e.preventDefault(); moveFocus(-1); break;
      case 'Enter': case 'o':
        e.preventDefault();
        if (!focusedKey) break;
        const link = document.querySelector('.cluster[data-key="' + esc2(focusedKey) + '"] .item.lead .title[data-reader]');
        if (link) link.click();
        break;
      case 'x': if (focusedKey) doArchive(focusedKey); break;
      case 's': if (focusedKey) doSnooze(focusedKey);  break;
      case 'b': if (focusedKey) doRL(focusedKey);      break;
      case 'm': if (focusedKey) doRead(focusedKey);    break;
      case 'n':
        if (!focusedKey) break;
        const trigger = document.querySelector('.note-area[data-key="' + esc2(focusedKey) + '"] .note-trigger');
        if (trigger) trigger.click();
        break;
      case 'r':
        if (focusedKey) {{
          const rt = document.querySelector('.cluster[data-key="' + esc2(focusedKey) + '"] .item.lead .title[data-reader]');
          if (rt) rt.click();
        }}
        break;
      case '/': e.preventDefault(); q.focus(); break;
      case '?': showShortcuts(); break;
      case 'Escape': setFocus(null); break;
    }}
  }});

  // click cluster body → focus (skip interactive elements)
  document.addEventListener('click', e => {{
    if (e.target.closest('button,a,.note-trigger,.read-ring')) return;
    const cl = e.target.closest('.cluster[data-key]');
    if (cl) setFocus(cl);
  }});

  // ── shortcuts overlay ─────────────────────────────────────────────────────
  function showShortcuts() {{
    if (document.getElementById('kbd-overlay')) {{ document.getElementById('kbd-overlay').remove(); return; }}
    const ov = document.createElement('div');
    ov.id = 'kbd-overlay';
    ov.style.cssText = 'position:fixed;inset:0;background:rgba(0,0,0,.45);z-index:999;display:flex;align-items:center;justify-content:center;';
    const box = document.createElement('div');
    box.style.cssText = 'background:var(--card);border:1px solid var(--rule);border-radius:14px;padding:20px 28px;min-width:280px;';
    box.innerHTML = '<h3 style="margin:0 0 12px;font-family:Georgia,serif;">Keyboard shortcuts</h3>' +
      '<table style="border-collapse:collapse;width:100%">' +
      '<tr><td style="font-family:monospace;color:var(--anchor);width:110px;padding:4px 8px;font-size:13.5px">j / ↓</td><td style="padding:4px 8px;font-size:13.5px">Next card</td></tr>' +
      '<tr><td style="font-family:monospace;color:var(--anchor);padding:4px 8px;font-size:13.5px">k / ↑</td><td style="padding:4px 8px;font-size:13.5px">Previous card</td></tr>' +
      '<tr><td style="font-family:monospace;color:var(--anchor);padding:4px 8px;font-size:13.5px">Enter / o / r</td><td style="padding:4px 8px;font-size:13.5px">Open in reader pane</td></tr>' +
      '<tr><td style="font-family:monospace;color:var(--anchor);padding:4px 8px;font-size:13.5px">m</td><td style="padding:4px 8px;font-size:13.5px">Toggle read</td></tr>' +
      '<tr><td style="font-family:monospace;color:var(--anchor);padding:4px 8px;font-size:13.5px">x</td><td style="padding:4px 8px;font-size:13.5px">Archive</td></tr>' +
      '<tr><td style="font-family:monospace;color:var(--anchor);padding:4px 8px;font-size:13.5px">s</td><td style="padding:4px 8px;font-size:13.5px">Snooze until tomorrow</td></tr>' +
      '<tr><td style="font-family:monospace;color:var(--anchor);padding:4px 8px;font-size:13.5px">b</td><td style="padding:4px 8px;font-size:13.5px">Save for later</td></tr>' +
      '<tr><td style="font-family:monospace;color:var(--anchor);padding:4px 8px;font-size:13.5px">n</td><td style="padding:4px 8px;font-size:13.5px">Add / edit note</td></tr>' +
      '<tr><td style="font-family:monospace;color:var(--anchor);padding:4px 8px;font-size:13.5px">/</td><td style="padding:4px 8px;font-size:13.5px">Focus search</td></tr>' +
      '<tr><td style="font-family:monospace;color:var(--anchor);padding:4px 8px;font-size:13.5px">?</td><td style="padding:4px 8px;font-size:13.5px">This help</td></tr>' +
      '<tr><td style="font-family:monospace;color:var(--anchor);padding:4px 8px;font-size:13.5px">Esc</td><td style="padding:4px 8px;font-size:13.5px">Clear focus</td></tr>' +
      '</table><p style="margin:10px 0 0;font-size:12px;color:var(--muted)">Press ? or click outside to close</p>';
    ov.appendChild(box);
    ov.addEventListener('click', e => {{ if (e.target === ov) ov.remove(); }});
    document.body.appendChild(ov);
  }}

  // ── dark mode ─────────────────────────────────────────────────────────────
  (function() {{
    const saved = ls('digest-theme');
    if (saved === 'dark') {{ document.documentElement.dataset.theme = 'dark'; themeBtn.textContent = 'Light'; }}
  }})();
  themeBtn.addEventListener('click', () => {{
    const dark = document.documentElement.dataset.theme !== 'dark';
    document.documentElement.dataset.theme = dark ? 'dark' : '';
    themeBtn.textContent = dark ? 'Light' : 'Dark';
    localStorage.setItem('digest-theme', dark ? 'dark' : '');
  }});

  // ── reading pane ──────────────────────────────────────────────────────────
  const readPane   = document.getElementById('reading-pane');
  const paneTitle  = readPane.querySelector('.pane-title');
  const paneCont   = readPane.querySelector('.pane-content');
  const paneByline = readPane.querySelector('.pane-byline');
  const paneSiteEl = readPane.querySelector('.pane-site');
  const paneLoad   = readPane.querySelector('.pane-loading');
  const paneErr    = readPane.querySelector('.pane-error');
  const paneNewTab = readPane.querySelector('.pane-newtab');
  const paneBody   = readPane.querySelector('.pane-body');
  let currentPaneUrl = '';

  readPane.querySelector('.pane-close').addEventListener('click', closePane);

  function closePane() {{
    readPane.classList.remove('open');
    document.body.classList.remove('pane-open');
    currentPaneUrl = '';
    hlTooltip.style.display = 'none';
  }}

  async function openInPane(url, title) {{
    if (currentPaneUrl === url && readPane.classList.contains('open')) {{ closePane(); return; }}
    currentPaneUrl = url;
    readPane.classList.add('open');
    document.body.classList.add('pane-open');
    paneTitle.textContent = title || '';
    paneByline.textContent = '';
    paneCont.innerHTML = '';
    paneSiteEl.textContent = '';
    paneNewTab.href = url;
    paneErr.style.display = 'none';
    paneLoad.style.display = '';
    paneBody.scrollTop = 0;

    try {{
      const res  = await fetch('/api/reader?url=' + encodeURIComponent(url));
      const data = await res.json();
      paneLoad.style.display = 'none';
      if (!res.ok || data.error) {{
        paneErr.style.display = '';
        paneErr.innerHTML = (data.error || 'Could not load.') +
          ' <a href="' + url + '" target="_blank" rel="noopener">Open in new tab ↗</a>';
        return;
      }}
      paneTitle.textContent    = data.title    || title || '';
      paneByline.textContent   = [data.byline, data.siteName].filter(Boolean).join(' \xb7 ');
      paneSiteEl.textContent   = data.siteName || '';
      paneCont.innerHTML       = data.content  || '';
      paneNewTab.href          = url;
      applyStoredHighlights(url);
    }} catch (err) {{
      paneLoad.style.display = 'none';
      if (window.location.protocol === 'file:') {{
        closePane();
        window.open(url, '_blank', 'noopener,noreferrer');
        return;
      }}
      paneErr.style.display  = '';
      paneErr.innerHTML = 'Network error. <a href="' + url + '" target="_blank" rel="noopener">Open in new tab ↗</a>';
    }}
  }}


  // ── highlights ────────────────────────────────────────────────────────────
  let hlStore  = objOf('digest-highlights');
  const hlTooltip = document.getElementById('hl-tooltip');
  const hlBtn     = document.getElementById('hl-btn');
  let pendingRange = null;

  paneCont.addEventListener('mouseup', () => {{
    const sel = window.getSelection();
    if (!sel || sel.isCollapsed) {{ hlTooltip.style.display = 'none'; return; }}
    const text = sel.toString().trim();
    if (!text || text.length < 3) {{ hlTooltip.style.display = 'none'; return; }}
    pendingRange = sel.getRangeAt(0).cloneRange();
    const rect = sel.getRangeAt(0).getBoundingClientRect();
    hlTooltip.style.display  = '';
    hlTooltip.style.top  = (rect.top  + window.scrollY - 42) + 'px';
    hlTooltip.style.left = (rect.left + rect.width / 2 - hlTooltip.offsetWidth / 2) + 'px';
  }});

  document.addEventListener('mousedown', e => {{
    if (!hlBtn.contains(e.target)) hlTooltip.style.display = 'none';
  }});

  hlBtn.addEventListener('click', () => {{
    if (!pendingRange || !currentPaneUrl) return;
    const text = pendingRange.toString().trim();
    if (!text) return;
    const mark = document.createElement('mark');
    mark.className = 'hl';
    try {{
      pendingRange.surroundContents(mark);
    }} catch (e) {{
      const frag = pendingRange.extractContents();
      mark.appendChild(frag);
      pendingRange.insertNode(mark);
    }}
    if (!hlStore[currentPaneUrl]) hlStore[currentPaneUrl] = [];
    if (!hlStore[currentPaneUrl].find(h => h.t === text))
      hlStore[currentPaneUrl].push({{ t: text }});
    lsSet('digest-highlights', hlStore);
    hlTooltip.style.display = 'none';
    window.getSelection().removeAllRanges();
  }});

  function applyStoredHighlights(url) {{
    const list = hlStore[url];
    if (!list || !list.length) return;
    list.forEach(h => {{
      const text = h.t;
      if (!text) return;
      const walker = document.createTreeWalker(paneCont, NodeFilter.SHOW_TEXT);
      let node;
      while ((node = walker.nextNode())) {{
        if (node.parentNode && node.parentNode.nodeName === 'MARK') continue;
        const idx = node.nodeValue.indexOf(text);
        if (idx === -1) continue;
        const before = node.nodeValue.slice(0, idx);
        const after  = node.nodeValue.slice(idx + text.length);
        const mark   = document.createElement('mark');
        mark.className = 'hl';
        mark.textContent = text;
        const parent = node.parentNode, next = node.nextSibling;
        parent.removeChild(node);
        if (before) parent.insertBefore(document.createTextNode(before), next);
        parent.insertBefore(mark, next);
        if (after)  parent.insertBefore(document.createTextNode(after),  next);
        break;
      }}
    }});
  }}

  // override Escape to close pane first
  document.addEventListener('keydown', e => {{
    if (e.key === 'Escape' && readPane.classList.contains('open')) {{
      e.stopImmediatePropagation();
      closePane();
    }}
  }}, true);  // capture phase so it runs before the nav keydown
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
            if lead.get("rbtl"):
                lines.append(f"  - *Reading between the lines: {lead['rbtl']}*")
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
