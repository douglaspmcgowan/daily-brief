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

# --- Ledger palette (DESIGN.md 'Colour'): nine hex colours per mode plus one shadow alpha ---
PALETTE = {
    "paper": "#f6f3ec",
    "sheet": "#fffdf8",
    "ink": "#1d1a16",
    "muted": "#6b6357",
    "rule": "#e3ddd0",
    "anchor": "#c8482b",
    "anchor_deep": "#a8391f",
    "highlight": "#fff176",
    "caution": "#7a5c00",
    "shadow": "rgba(29,26,22,.14)",
}

PALETTE_DARK = {
    "paper": "#1c1914",
    "sheet": "#252017",
    "ink": "#ede9e0",
    "muted": "#9a9088",
    "rule": "#3b342a",
    "anchor": "#e06750",
    "anchor_deep": "#e06750",
    "highlight": "#4a3d00",
    "caution": "#d9b64a",
    "shadow": "rgba(0,0,0,.5)",
}


def _palette_tokens(p: dict) -> str:
    """Render one palette as custom-property declarations, at its current values."""
    return (f"--paper:{p['paper']}; --sheet:{p['sheet']}; --ink:{p['ink']};\n"
            f"    --muted:{p['muted']}; --rule:{p['rule']}; --anchor:{p['anchor']};\n"
            f"    --anchor-deep:{p['anchor_deep']}; --highlight:{p['highlight']};\n"
            f"    --caution:{p['caution']}; --shadow:{p['shadow']};")


LIGHT_TOKENS = _palette_tokens(PALETTE)
DARK_TOKENS = _palette_tokens(PALETTE_DARK)

FONTS_HREF = ("https://fonts.googleapis.com/css2?family=Playfair+Display:ital,wght@0,700;0,900;1,700"
              "&family=PT+Serif:ital,wght@0,400;0,700;1,400&display=swap")

# Phosphor 2.1.1 path data, unmodified (DESIGN.md 'Icons'): bold at rest, fill for a toggled-on state.
ICON_EXT = '<svg class="ico" viewBox="0 0 256 256" fill="currentColor" aria-hidden="true"><path d="M204,64V168a12,12,0,0,1-24,0V93L72.49,200.49a12,12,0,0,1-17-17L163,76H88a12,12,0,0,1,0-24H192A12,12,0,0,1,204,64Z"/></svg>'
ICON_BOOKMARK = '<svg class="ico" viewBox="0 0 256 256" fill="currentColor" aria-hidden="true"><path d="M184,28H72A20,20,0,0,0,52,48V224a12,12,0,0,0,18.36,10.18l57.63-36,57.65,36A12,12,0,0,0,204,224V48A20,20,0,0,0,184,28Zm-4,174.35-45.65-28.53a12,12,0,0,0-12.72,0L76,202.35V52H180Z"/></svg>'
ICON_BOOKMARK_FILL = '<svg class="ico fill" viewBox="0 0 256 256" fill="currentColor" aria-hidden="true"><path d="M184,32H72A16,16,0,0,0,56,48V224a8,8,0,0,0,12.24,6.78L128,193.43l59.77,37.35A8,8,0,0,0,200,224V48A16,16,0,0,0,184,32Z"/></svg>'
ICON_SNOOZE = '<svg class="ico" viewBox="0 0 256 256" fill="currentColor" aria-hidden="true"><path d="M236.37,139.4a12,12,0,0,0-12-3A84.07,84.07,0,0,1,119.6,31.59a12,12,0,0,0-15-15A108.86,108.86,0,0,0,49.69,55.07,108,108,0,0,0,136,228a107.09,107.09,0,0,0,64.93-21.69,108.86,108.86,0,0,0,38.44-54.94A12,12,0,0,0,236.37,139.4Zm-49.88,47.74A84,84,0,0,1,68.86,69.51,84.93,84.93,0,0,1,92.27,48.29Q92,52.13,92,56A108.12,108.12,0,0,0,200,164q3.87,0,7.71-.27A84.79,84.79,0,0,1,186.49,187.14Z"/></svg>'
ICON_SNOOZE_FILL = '<svg class="ico fill" viewBox="0 0 256 256" fill="currentColor" aria-hidden="true"><path d="M235.54,150.21a104.84,104.84,0,0,1-37,52.91A104,104,0,0,1,32,120,103.09,103.09,0,0,1,52.88,57.48a104.84,104.84,0,0,1,52.91-37,8,8,0,0,1,10,10,88.08,88.08,0,0,0,109.8,109.8,8,8,0,0,1,10,10Z"/></svg>'
ICON_ARCHIVE = '<svg class="ico" viewBox="0 0 256 256" fill="currentColor" aria-hidden="true"><path d="M224,44H32A20,20,0,0,0,12,64V88a20,20,0,0,0,16,19.6V192a20,20,0,0,0,20,20H208a20,20,0,0,0,20-20V107.6A20,20,0,0,0,244,88V64A20,20,0,0,0,224,44ZM36,68H220V84H36ZM52,188V108H204v80Zm112-52a12,12,0,0,1-12,12H104a12,12,0,0,1,0-24h48A12,12,0,0,1,164,136Z"/></svg>'
ICON_CHECK = '<svg class="ico" viewBox="0 0 256 256" fill="currentColor" aria-hidden="true"><path d="M232.49,80.49l-128,128a12,12,0,0,1-17,0l-56-56a12,12,0,1,1,17-17L96,183,215.51,63.51a12,12,0,0,1,17,17Z"/></svg>'
ICON_CHECK_FILL = '<svg class="ico fill" viewBox="0 0 256 256" fill="currentColor" aria-hidden="true"><path d="M128,24A104,104,0,1,0,232,128,104.11,104.11,0,0,0,128,24Zm45.66,85.66-56,56a8,8,0,0,1-11.32,0l-24-24a8,8,0,0,1,11.32-11.32L112,148.69l50.34-50.35a8,8,0,0,1,11.32,11.32Z"/></svg>'
ICON_EDIT = '<svg class="ico" viewBox="0 0 256 256" fill="currentColor" aria-hidden="true"><path d="M230.14,70.54,185.46,25.85a20,20,0,0,0-28.29,0L33.86,149.17A19.85,19.85,0,0,0,28,163.31V208a20,20,0,0,0,20,20H92.69a19.86,19.86,0,0,0,14.14-5.86L230.14,98.82a20,20,0,0,0,0-28.28ZM91,204H52V165l84-84,39,39ZM192,103,153,64l18.34-18.34,39,39Z"/></svg>'
ICON_CLOSE = '<svg class="ico" viewBox="0 0 256 256" fill="currentColor" aria-hidden="true"><path d="M208.49,191.51a12,12,0,0,1-17,17L128,145,64.49,208.49a12,12,0,0,1-17-17L111,128,47.51,64.49a12,12,0,0,1,17-17L128,111l63.51-63.52a12,12,0,0,1,17,17L145,128Z"/></svg>'
ICON_STAR = '<svg class="ico fill" viewBox="0 0 256 256" fill="currentColor" role="img" aria-label="Pinned"><path d="M234.29,114.85l-45,38.83L203,211.75a16.4,16.4,0,0,1-24.5,17.82L128,198.49,77.47,229.57A16.4,16.4,0,0,1,53,211.75l13.76-58.07-45-38.83A16.46,16.46,0,0,1,31.08,86l59-4.76,22.76-55.08a16.36,16.36,0,0,1,30.27,0l22.75,55.08,59,4.76a16.46,16.46,0,0,1,9.37,28.86Z"/></svg>'
ICON_GRIP = '<svg class="ico" viewBox="0 0 256 256" fill="currentColor" aria-hidden="true"><path d="M108,60A16,16,0,1,1,92,44,16,16,0,0,1,108,60Zm56,16a16,16,0,1,0-16-16A16,16,0,0,0,164,76ZM92,112a16,16,0,1,0,16,16A16,16,0,0,0,92,112Zm72,0a16,16,0,1,0,16,16A16,16,0,0,0,164,112ZM92,180a16,16,0,1,0,16,16A16,16,0,0,0,92,180Zm72,0a16,16,0,1,0,16,16A16,16,0,0,0,164,180Z"/></svg>'
ICON_SEARCH = '<svg class="ico" viewBox="0 0 256 256" fill="currentColor" aria-hidden="true"><path d="M232.49,215.51,185,168a92.12,92.12,0,1,0-17,17l47.53,47.54a12,12,0,0,0,17-17ZM44,112a68,68,0,1,1,68,68A68.07,68.07,0,0,1,44,112Z"/></svg>'
ICONS_JS = json.dumps({
    'read': [ICON_CHECK, ICON_CHECK_FILL],
    'rl': [ICON_BOOKMARK, ICON_BOOKMARK_FILL],
    'snooze': [ICON_SNOOZE, ICON_SNOOZE_FILL],
})

# Type, spacing, rules, motion and status tokens (DESIGN.md 'Type', 'Spacing, radii, rules,
# elevation', 'Motion tokens'). Mode-independent: colours resolve through var() per element.
SCALE_TOKENS = """--font-display:"Playfair Display", Georgia, "Times New Roman", serif;
    --font-body:"PT Serif", Georgia, "Iowan Old Style", serif;
    --fs-sm:0.85rem; --fs-md:1.0625rem; --fs-display:clamp(2.125rem, 6vw + 0.75rem, 3.25rem);
    --sp-4:4px; --sp-8:8px; --sp-12:12px; --sp-16:16px; --sp-24:24px; --sp-32:32px;
    --sp-48:48px; --sp-64:64px;
    --wrap:70rem; --measure:68ch; --radius-0:0;
    --rule-hair:1px solid var(--rule); --rule-firm:1px solid var(--ink); --rule-double:4px double var(--ink);
    --dur-1:120ms; --dur-2:200ms; --dur-3:320ms;
    --ease-out:cubic-bezier(.22,1,.36,1); --ease-in:cubic-bezier(.4,0,1,1);
    --status-new:var(--anchor-deep); --status-error:var(--anchor-deep); --status-caution:var(--caution);
    --status-done:var(--muted); --status-saved:var(--ink);"""


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
    new_badge = '<span class="badge">New</span>' if it.get("is_new") else ""
    src = esc(it.get("source", ""))
    stype = esc(it.get("source_type", ""))
    title = esc(it.get("title", "(untitled)"))
    url = esc(it.get("url", "#"))
    summary = esc(it.get("summary", ""))
    pin = f'<span class="pin" title="pinned / evergreen">{ICON_STAR}</span>' if it.get("pinned") else ""
    cls = "item lead" if lead else "item also"
    rbtl = esc(it.get("rbtl", ""))
    search_blob = esc(" ".join([it.get("title", ""), it.get("summary", ""),
                                it.get("rbtl", ""), it.get("source", ""),
                                " ".join(it.get("topics", []))])).lower()
    summ_html = f'<p class="summary">{summary}</p>' if (summary and lead) else ""
    rbtl_html = (f'<p class="rbtl"><span class="rbtl-label">Reading between the lines.</span> '
                 f'{rbtl}</p>') if (rbtl and lead) else ""

    # date stamp
    fs_date = parse_date(it.get("first_seen"))
    age_str = _age_label(fs_date, run_date)
    raw_date = esc(str(it.get("first_seen", ""))[:10])
    date_html = (f'<span class="date-stamp" title="{raw_date}"><span class="dot" aria-hidden="true">|</span>{esc(age_str)}</span>'
                 ) if age_str else ""

    # card action buttons and reader trigger (lead cards only)
    if lead and cluster_key:
        k = esc(cluster_key)
        reader_attr = ' data-reader="1"'
        ext_link = f'<a class="ext-link" href="{url}" target="_blank" rel="noopener" data-tip="Open in new tab" aria-label="Open in new tab">{ICON_EXT}</a>'
        actions_html = (
            f'<div class="card-actions">'
            f'<button class="card-btn read-btn" data-key="{k}" data-tip="Mark read (m)" aria-label="Mark read" aria-pressed="false">{ICON_CHECK}</button>'
            f'<button class="card-btn rl-btn" data-key="{k}" data-tip="Save for later (b)" aria-label="Save for later" aria-pressed="false">{ICON_BOOKMARK}</button>'
            f'<button class="card-btn snooze-btn" data-key="{k}" data-tip="Snooze until tomorrow (s)" aria-label="Snooze until tomorrow" aria-pressed="false">{ICON_SNOOZE}</button>'
            f'<button class="card-btn dismiss-btn" data-key="{k}" data-tip="Archive (x)" aria-label="Archive">{ICON_ARCHIVE}</button>'
            f'</div>'
        )
    else:
        reader_attr = ""
        ext_link = ""
        actions_html = ""

    return f"""<article class="{cls}" data-search="{search_blob}">
  <div class="item-head-main">
    <a class="title" href="{url}" target="_blank" rel="noopener"{reader_attr}>{title}</a>
    {new_badge}{pin}{ext_link}
  </div>
  <div class="item-body">{summ_html}{rbtl_html}</div>
  <div class="item-rail">
    <div class="meta"><span class="src">{src}</span><span class="dot" aria-hidden="true">|</span><span class="stype">{stype}</span>{date_html}</div>
    {actions_html}
  </div>
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
    drag_handle = f'<div class="drag-handle" data-tip="Drag to reorder">{ICON_GRIP}</div>'
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
            f' <span class="new-src">{esc(it.get("source",""))}, {esc(TOPIC_LABELS.get(it.get("topic","tech"),""))}</span></li>'
            for it in new_items
        )
        whats_new = f'<section class="whatsnew"><h2>New since last digest</h2><ol>{new_rows}</ol></section>'
    else:
        whats_new = ('<section class="whatsnew"><h2>New since last digest</h2>'
                     '<p class="empty">Nothing new since the last digest.</p></section>')

    # daily insight — top-scored new item with an rbtl
    top_rbtl = sorted([it for it in items if it.get("is_new") and it.get("rbtl")],
                      key=score, reverse=True)
    if top_rbtl:
        ins = top_rbtl[0]
        insight_html = (
            f'<section class="insight-card" aria-label="Today\'s insight">'
            f'<blockquote class="insight-quote">{esc(ins.get("rbtl",""))}</blockquote>'
            f'<div class="insight-src"><a href="{esc(ins.get("url","#"))}" target="_blank" rel="noopener">'
            f'{esc(ins.get("title",""))}</a>'
            f'<span class="insight-from"> — {esc(ins.get("source",""))}</span></div>'
            f'</section>'
        )
    else:
        insight_html = ""

    pills = "".join(
        f'<button class="pill{" zero" if not counts[t] else ""}" data-filter="{t}" aria-pressed="false">'
        f'{esc(TOPIC_LABELS[t])} <span class="pc">{counts[t]}</span></button>'
        for t in TOPICS
    )

    refs_html = render_references_html(references)
    stamp = f"{run_date.strftime('%A, %B')} {run_date.day}, {run_date.year}"

    return f"""<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<meta name="theme-color" content="{PALETTE['paper']}" media="(prefers-color-scheme: light)">
<meta name="theme-color" content="{PALETTE_DARK['paper']}" media="(prefers-color-scheme: dark)">
<meta name="description" content="A personal news digest on AI, design and technology, rebuilt each run from a persistent corpus.">
<meta property="og:type" content="website">
<meta property="og:title" content="The Daily Brief">
<meta property="og:description" content="A personal news digest on AI, design and technology.">
<meta property="og:image" content="/og-image.png">
<meta name="twitter:card" content="summary_large_image">
<link rel="icon" href="data:image/svg+xml,<svg viewBox='0 0 44 44' fill='none' xmlns='http://www.w3.org/2000/svg'><rect x='3' y='6' width='29' height='32' rx='5' stroke='%23c8482b' stroke-width='2.5'/><line x1='10' y1='15' x2='26' y2='15' stroke='%23c8482b' stroke-width='2.5' stroke-linecap='round'/><line x1='10' y1='21' x2='26' y2='21' stroke='%23c8482b' stroke-width='2.5' stroke-linecap='round'/><line x1='10' y1='27' x2='20' y2='27' stroke='%23c8482b' stroke-width='2.5' stroke-linecap='round'/><circle cx='36' cy='11' r='7' fill='%23c8482b'/><circle cx='36' cy='11' r='3.5' fill='white' opacity='.9'/></svg>" type="image/svg+xml">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="{FONTS_HREF}">
<title>News Digest — {stamp}</title>
<style>
  :root {{
    {LIGHT_TOKENS}
    {SCALE_TOKENS}
  }}
  * {{ box-sizing:border-box; }}
  body {{ margin:0; background:var(--paper); color:var(--ink);
    font-family:var(--font-body); font-size:var(--fs-md);
    line-height:1.5; }}
  .wrap {{ max-width:var(--wrap); margin:0 auto; padding:0 clamp(var(--sp-16), 4vw, var(--sp-24)) var(--sp-64); }}
  header.mast {{ border-bottom:var(--rule-double); padding:clamp(var(--sp-24), 5vw, var(--sp-32)) 0 var(--sp-16); margin-bottom:var(--sp-8); }}
  .mast-title {{ font-family:var(--font-display); font-weight:900;
    font-size:var(--fs-display); line-height:1; letter-spacing:-.02em; margin:0; }}
  .mast-title .accent {{ color:var(--anchor); }}
  .mast-sub {{ color:var(--muted); margin:var(--sp-8) 0 0; font-size:var(--fs-md);
    display:flex; gap:var(--sp-12); flex-wrap:wrap; align-items:center; }}
  .mast-sub b {{ color:var(--ink); font-weight:700; }}
  .controls {{ position:sticky; top:0; background:var(--paper); padding:var(--sp-8) 0;
    border-bottom:var(--rule-hair); z-index:5;
    display:flex; flex-wrap:wrap; gap:var(--sp-8); align-items:center; }}
  .pills-row {{ display:flex; flex-wrap:wrap; gap:var(--sp-8); align-items:center; flex:1; min-width:0; }}
  .pill, .arc-pill, #theme-btn {{ font:inherit; font-size:var(--fs-sm); border:var(--rule-firm); background:transparent;
    color:var(--ink); padding:var(--sp-8) var(--sp-12); border-radius:var(--radius-0); cursor:pointer;
    touch-action:manipulation; min-height:44px; min-width:44px; white-space:nowrap;
    transition:background-color var(--dur-1) var(--ease-out),color var(--dur-1) var(--ease-out); }}
  .pill:hover, .arc-pill:hover, #theme-btn:hover,
  .pill:active, .arc-pill:active, #theme-btn:active {{ background:var(--ink); color:var(--paper); }}
  .pill[aria-pressed="true"], .arc-pill[aria-pressed="true"] {{ background:var(--ink); color:var(--paper); }}
  .pill.zero {{ color:var(--muted); }}
  .pill.zero:hover, .pill.zero:active, .pill.zero[aria-pressed="true"] {{ color:var(--paper); }}
  .pill .pc {{ font-variant-numeric:tabular-nums; margin-left:var(--sp-4); }}
  .search-row {{ display:flex; flex-wrap:wrap; gap:var(--sp-8); align-items:center; }}
  .search-field {{ position:relative; flex:1 1 160px; min-width:0; display:flex; align-items:center; }}
  .search-field .ico {{ position:absolute; left:var(--sp-12); color:var(--muted); pointer-events:none; }}
  #q {{ font:inherit; width:100%; min-width:0; min-height:44px; padding:var(--sp-8) var(--sp-12) var(--sp-8) calc(var(--sp-24) + var(--sp-16));
    border:var(--rule-firm); border-radius:var(--radius-0); background:var(--sheet); color:var(--ink); }}
  #q::placeholder {{ color:var(--muted); opacity:1; }}
  .front {{ container-type:inline-size; }}
  .front-grid {{ display:grid; grid-template-columns:minmax(0,1fr); grid-template-areas:"side" "index";
    column-gap:var(--sp-48); align-items:start; }}
  .front-grid.solo {{ grid-template-areas:"index"; }}
  @container (min-width:800px) {{
    .front-grid {{ grid-template-columns:minmax(0,2fr) minmax(0,1fr); grid-template-areas:"index side"; }}
    .front-grid.solo {{ grid-template-columns:minmax(0,1fr); grid-template-areas:"index"; }}
  }}
  .whatsnew {{ grid-area:index; background:transparent; border:0; border-top:var(--rule-double); border-bottom:var(--rule-hair);
    border-radius:var(--radius-0); padding:var(--sp-16) 0; margin:var(--sp-24) 0; }}
  .whatsnew h2 {{ margin:0 0 var(--sp-8); font-size:var(--fs-md); font-weight:700;
    color:var(--anchor-deep); }}
  .whatsnew ol {{ margin:0; padding-left:var(--sp-24); }}
  .whatsnew li + li {{ border-top:var(--rule-hair); }}
  .whatsnew li, .also-list li, .ref-list li {{ margin:0; padding:var(--sp-12) 0; line-height:1.6; }}
  .whatsnew a {{ color:var(--ink); text-decoration:none; font-weight:700; }}
  .whatsnew a:hover {{ text-decoration:underline; }}
  .new-src {{ color:var(--muted); font-weight:400; font-style:italic; font-size:var(--fs-sm); }}
  .topic {{ margin:clamp(var(--sp-24), 5vw, var(--sp-32)) 0 0; }}
  .topic-h {{ font-family:var(--font-display); font-size:var(--fs-md); font-weight:900; margin:0 0 var(--sp-12);
    padding-top:var(--sp-12); border-top:var(--rule-double); }}
  .topic-h .count {{ font-size:var(--fs-sm); color:var(--muted); font-family:inherit;
    vertical-align:middle; }}
  .cluster {{ margin:0; padding:var(--sp-16) 0 var(--sp-8); border-bottom:var(--rule-hair); container-type:inline-size; }}
  .topic-h + .cluster {{ padding-top:var(--sp-8); }}
  /* story: unboxed. One column below 800px of its own container; above it a text column and a meta rail. */
  .item {{ display:grid; grid-template-columns:minmax(0,1fr); column-gap:var(--sp-48);
    grid-template-areas:"head" "meta" "body" "actions"; margin:0; padding:0; }}
  .item-head-main {{ grid-area:head; min-width:0; display:flex; align-items:baseline; gap:var(--sp-8); flex-wrap:wrap; }}
  .item-body {{ grid-area:body; min-width:0; }}
  .item-rail {{ display:contents; }}
  .item-rail .meta {{ grid-area:meta; }}
  .item-rail .card-actions {{ grid-area:actions; }}
  @container (min-width:800px) {{
    .item {{ grid-template-columns:minmax(0,var(--measure)) minmax(12rem,1fr);
      grid-template-areas:"head rail" "body rail"; }}
    .item-rail {{ display:block; grid-area:rail; align-self:start; }}
    .item-rail .meta {{ margin-top:0; }}
    .item-rail .meta > span {{ display:block; }}
    .item-rail .meta .dot {{ display:none; }}
    .item-rail .card-actions {{ margin-top:var(--sp-8); flex-wrap:wrap; }}
  }}
  .title {{ color:var(--ink); text-decoration:none; font-size:var(--fs-md); font-weight:700;
    font-family:var(--font-display); padding:var(--sp-12) 0; margin:calc(-1*var(--sp-12)) 0;
    transition:color var(--dur-1) var(--ease-out); }}
  .title[data-reader] {{ cursor:pointer; }}
  .title:hover {{ color:var(--anchor-deep); text-decoration:underline; }}
  .ext-link {{ color:var(--muted); font-size:var(--fs-sm); text-decoration:none; opacity:.55;
    flex-shrink:0; display:inline-flex; align-items:center; justify-content:center;
    min-width:44px; min-height:44px; margin:calc(-1*var(--sp-12)) 0;
    transition:opacity var(--dur-1) var(--ease-out),color var(--dur-1) var(--ease-out); }}
  .ext-link:hover {{ opacity:1; color:var(--ink); }}
  .badge {{ background:var(--status-new); color:var(--paper); font-size:var(--fs-sm); font-weight:700;
    padding:var(--sp-4) var(--sp-8); border-radius:var(--radius-0); }}
  .pin {{ color:var(--anchor); }}
  .meta {{ color:var(--muted); font-size:var(--fs-sm); margin-top:var(--sp-4); }}
  .meta .dot {{ margin:0 var(--sp-4); }}
  .summary {{ margin:var(--sp-8) 0 0; color:var(--ink); font-size:var(--fs-md); max-width:var(--measure); }}
  .rbtl {{ margin:var(--sp-8) 0 0; font-size:var(--fs-md); color:var(--muted); font-style:italic; line-height:1.5; max-width:var(--measure); }}
  .rbtl-label {{ font-style:normal; font-weight:700; color:var(--anchor-deep); }}
  .also-wrap {{ margin:var(--sp-4) 0 0 var(--sp-4); }}
  .also-wrap summary {{ cursor:pointer; color:var(--ink); font-size:var(--fs-sm); line-height:1.6; padding:var(--sp-12) 0; }}
  .also-list {{ margin:var(--sp-8) 0 var(--sp-4); padding-left:var(--sp-16); }}
  .also-list li {{ font-size:var(--fs-sm); }}
  .whatsnew a, .also-list a, .ref-list a {{ display:inline-block; vertical-align:top; padding:var(--sp-12) 0; margin:calc(-1*var(--sp-12)) 0; }}
  .insight-src a {{ display:inline-block; padding:var(--sp-12) 0; line-height:1.7; }}
  .also-list a {{ color:var(--ink); }}
  .also-src {{ color:var(--muted); font-size:var(--fs-sm); }}
  .empty {{ color:var(--muted); font-style:italic; margin:var(--sp-8) 0; padding:var(--sp-12) 0; border-bottom:var(--rule-hair); }}
  .whatsnew .empty {{ margin:0; padding:var(--sp-8) 0 0; border:0; }}
  .no-results {{ margin:var(--sp-48) 0; text-align:center; color:var(--muted); }}
  .no-results[hidden] {{ display:none; }}
  .references {{ margin:var(--sp-48) 0 0; border-top:var(--rule-double); padding-top:var(--sp-16); }}
  .references h2 {{ font-family:var(--font-display); font-size:var(--fs-md); font-weight:700; margin:0 0 var(--sp-4); }}
  .ref-lead {{ color:var(--muted); font-size:var(--fs-sm); margin:0 0 var(--sp-12); }}
  .references {{ container-type:inline-size; }}
  .ref-list {{ columns:1; column-gap:var(--sp-24); column-rule:var(--rule-hair); margin:0; padding:0; list-style:none; }}
  .ref-list li {{ break-inside:avoid; }}
  @container (min-width:520px) {{ .ref-list {{ columns:2; }} }}
  @container (min-width:900px) {{ .ref-list {{ columns:3; }} }}
  .ref-note {{ color:var(--muted); font-size:var(--fs-sm); }}
  a {{ color:var(--ink); text-decoration:underline; text-decoration-thickness:1px;
    transition:color var(--dur-1) var(--ease-out); }}
  footer.foot {{ margin-top:var(--sp-32); color:var(--muted); font-size:var(--fs-sm);
    border-top:var(--rule-hair); padding-top:var(--sp-12); }}
  @media (max-width:600px) {{
    .mast-sub {{ font-size:var(--fs-sm); gap:var(--sp-4); }}
    .mast-topics {{ display:none; }}
    .controls {{ flex-direction:column; flex-wrap:nowrap; align-items:stretch; gap:var(--sp-8); }}
    .pills-row {{ flex-wrap:wrap; gap:var(--sp-4); }}
    .search-row {{ gap:var(--sp-4); }}
    #q {{ min-width:0; font-size:var(--fs-md); }}
    .title {{ line-height:1.35; }}
    .whatsnew {{ padding:var(--sp-12) 0; }}
    .drag-handle {{ opacity:.35; left:-14px; }}
    .topic-ring {{ width:16px; height:16px; }}
    .topic-ring-label {{ font-size:var(--fs-sm); }}
  }}
  @media (hover:none) {{
    .drag-handle {{ opacity:.3; }}
    .cluster:hover .drag-handle {{ opacity:.3; }}
  }}
  /* masthead logo */
  .mast-logo-row {{ display:flex; align-items:center; gap:var(--sp-12); }}
  .mast-logo {{ width:44px; height:44px; color:var(--ink); flex-shrink:0; }}
  /* card actions + kanban */
  .card-actions {{ display:flex; align-items:center; gap:var(--sp-8); }}
  .ico {{ width:1.15em; height:1.15em; fill:currentColor; flex-shrink:0; }}
  /* story actions: borderless 44px squares; toggled on = fill-weight icon + aria-pressed */
  .card-btn {{ font:inherit; width:44px; height:44px; border-radius:var(--radius-0); border:1px solid transparent;
    background-color:transparent; color:var(--muted); font-size:var(--fs-md); line-height:1; cursor:pointer;
    display:flex; align-items:center; justify-content:center; padding:0; touch-action:manipulation;
    transition:background-color var(--dur-1) var(--ease-out),border-color var(--dur-1) var(--ease-out),color var(--dur-1) var(--ease-out); }}
  .card-btn:hover {{ border-color:var(--ink); color:var(--ink); }}
  .card-btn:active {{ background-color:var(--ink); color:var(--paper); }}
  .dismiss-btn:hover {{ background-color:var(--anchor-deep); border-color:var(--anchor-deep); color:var(--paper); }}
  .read-btn[aria-pressed="true"] {{ color:var(--status-done); }}
  .rl-btn[aria-pressed="true"] {{ color:var(--status-saved); }}
  .snooze-btn[aria-pressed="true"] {{ color:var(--status-caution); }}
  .cluster.is-read .item-head-main, .cluster.is-read .meta, .cluster.is-read .summary, .cluster.is-read .rbtl {{ opacity:.55; }}
  .item-head-main, .meta, .summary, .rbtl {{ transition:opacity var(--dur-2) var(--ease-out); }}
  /* disabled: defined for every control, no hover response */
  button:disabled, button[aria-disabled="true"], a[aria-disabled="true"] {{ opacity:.45; cursor:not-allowed; pointer-events:none; }}
  /* topic-level read progress ring */
  .topic-progress {{ display:inline-flex; align-items:center; gap:var(--sp-4); margin-left:var(--sp-12);
    vertical-align:middle; }}
  .topic-ring {{ width:20px; height:20px; flex-shrink:0; }}
  .topic-ring .ring-bg {{ fill:none; stroke:var(--rule); stroke-width:2.5; }}
  .topic-ring .ring-fg {{ fill:none; stroke:var(--anchor); stroke-width:2.5;
    stroke-dasharray:56.55; stroke-dashoffset:56.55;
    transition:stroke-dashoffset var(--dur-3) var(--ease-out); transform:rotate(-90deg); transform-origin:center; }}
  .topic-ring-label {{ font-size:var(--fs-sm); color:var(--muted); font-variant-numeric:tabular-nums; }}
  .date-stamp {{ color:var(--muted); font-size:var(--fs-sm); }}
  /* drag handle */
  .cluster {{ position:relative; }}
  .drag-handle {{ position:absolute; top:var(--sp-8); left:-18px; color:var(--muted); font-size:var(--fs-sm);
    cursor:grab; opacity:0; transition:opacity var(--dur-1) var(--ease-out); line-height:1; user-select:none; padding:var(--sp-4); }}
  .cluster:hover .drag-handle {{ opacity:1; }}
  .cluster[draggable] {{ cursor:default; }}
  .cluster.drag-over {{ outline:2px dashed var(--anchor); outline-offset:4px; border-radius:var(--radius-0); }}
  .cluster.dragging {{ opacity:.35; pointer-events:none; }}
  /* keyboard-navigation focus state — a ring, not a coloured left bar (banned) */
  .cluster.focused > .item.lead {{ outline:2px solid var(--anchor); outline-offset:var(--sp-8);
    transition:outline-color var(--dur-2) var(--ease-out); scroll-margin:var(--sp-64); }}
  /* tooltips */
  [data-tip] {{ position:relative; }}
  [data-tip]::after {{ content:attr(data-tip); position:absolute; bottom:calc(100% + 7px);
    left:50%; transform:translateX(-50%); background:var(--ink); color:var(--paper);
    font-size:var(--fs-sm); font-family:var(--font-body);
    font-weight:400; padding:var(--sp-4) var(--sp-8); border-radius:var(--radius-0); white-space:nowrap;
    pointer-events:none; opacity:0; transition:opacity var(--dur-1) var(--ease-out); z-index:20; }}
  [data-tip]:hover::after {{ opacity:1; }}
  .card-actions [data-tip]::after, .ext-link[data-tip]::after, #help-btn[data-tip]::after {{ left:auto; right:0; transform:none; }}
  #help-btn {{ width:44px; height:44px; padding:0; display:inline-flex; align-items:center;
    justify-content:center; font-size:var(--fs-sm); font-weight:700; }}
  /* note area */
  .note-area {{ padding:var(--sp-4) var(--sp-4) var(--sp-4); }}
  .note-trigger {{ font:inherit; font-size:var(--fs-sm); color:var(--ink); background-color:transparent;
    border:var(--rule-firm); border-radius:var(--radius-0); cursor:pointer;
    padding:var(--sp-4) var(--sp-12); display:inline-flex; align-items:center; gap:var(--sp-8); min-height:44px;
    transition:background-color var(--dur-1) var(--ease-out),color var(--dur-1) var(--ease-out); user-select:none; }}
  .note-trigger .ico {{ width:1.15em; height:1.15em; }}
  .note-trigger:hover, .note-trigger:active {{ background:var(--ink); color:var(--paper); }}
  .note-trigger.has-note {{ font-weight:700; }}
  .note-body {{ margin:var(--sp-4) 0 var(--sp-4); }}
  .note-input {{ width:100%; font:inherit; font-size:var(--fs-sm); resize:none;
    border:var(--rule-firm); border-radius:var(--radius-0); background:var(--sheet); color:var(--ink);
    padding:var(--sp-8) var(--sp-8); }}
  .note-display {{ font-size:var(--fs-sm); color:var(--muted); white-space:pre-wrap;
    padding:var(--sp-4) var(--sp-4) var(--sp-4); font-style:italic; display:none; border-left:1px solid var(--rule);
    margin-left:var(--sp-4); padding-left:var(--sp-12); }}
  .note-display.visible {{ display:block; }}
  /* insight card */
  .insight-card {{ grid-area:side; margin:var(--sp-24) 0; padding:var(--sp-16) 0; border-radius:var(--radius-0);
    background:transparent; border:0; border-top:var(--rule-double); border-bottom:var(--rule-hair); }}
  .insight-quote {{ margin:0 0 var(--sp-8); font-size:var(--fs-md); line-height:1.6;
    color:var(--ink); font-style:italic; }}
  .insight-src {{ font-size:var(--fs-sm); color:var(--muted); }}
  .insight-src a {{ color:var(--ink); font-weight:700; text-decoration:none; }}
  .insight-src a:hover {{ text-decoration:underline; }}
  .insight-from {{ color:var(--muted); }}
  :root[data-theme="dark"] {{
    {DARK_TOKENS}
  }}
  /* Follow the operating system when the reader has not chosen a theme. */
  @media (prefers-color-scheme: dark) {{
    :root:not([data-theme="light"]) {{
      {DARK_TOKENS}
    }}
  }}
  /* ── reading pane ──────────────────────────────────────────────────────── */
  .reading-pane {{ display:flex; visibility:hidden; opacity:0; transform:translateX(16px);
    position:fixed; top:0; right:0; width:40vw; height:100vh;
    background:var(--sheet); z-index:50;
    flex-direction:column; box-shadow:0 0 32px var(--shadow);
    transition:opacity var(--dur-2) var(--ease-in),transform var(--dur-2) var(--ease-in),visibility 0s var(--ease-in) var(--dur-2); }}
  .reading-pane.open {{ visibility:visible; opacity:1; transform:none;
    transition:opacity var(--dur-3) var(--ease-out),transform var(--dur-3) var(--ease-out),visibility 0s var(--ease-out); }}
  body.pane-open .wrap {{ margin-right:calc(40vw + var(--sp-32)); }}
  .pane-toolbar {{ display:flex; align-items:center; padding:var(--sp-8) var(--sp-12); border-bottom:var(--rule-hair);
    gap:var(--sp-8); flex-shrink:0; position:sticky; top:0; background:var(--sheet); z-index:2; }}
  .pane-site {{ font-size:var(--fs-sm); color:var(--muted); font-variant-numeric:tabular-nums; }}
  .pane-close,.pane-newtab {{ width:44px; height:44px; border-radius:var(--radius-0); border:1px solid transparent;
    background:transparent; color:var(--muted); font-size:var(--fs-md); cursor:pointer; display:flex;
    align-items:center; justify-content:center;
    transition:border-color var(--dur-1) var(--ease-out),color var(--dur-1) var(--ease-out); text-decoration:none; flex-shrink:0; }}
  .pane-close:hover,.pane-newtab:hover {{ border-color:var(--ink); color:var(--ink); }}
  .pane-body {{ flex:1; overflow-y:auto; padding:var(--sp-24) var(--sp-24) var(--sp-64); }}
  .pane-loading {{ color:var(--muted); font-style:italic; padding:var(--sp-12) 0; border-top:var(--rule-hair);
    border-bottom:var(--rule-hair); animation:pulse 1.4s var(--ease-out) infinite; }}
  @keyframes pulse {{ 0%,100% {{ opacity:.5; }} 50% {{ opacity:1; }} }}
  .pane-error {{ color:var(--status-error); font-size:var(--fs-sm); font-weight:700; padding:var(--sp-12) 0;
    border-top:var(--rule-double); line-height:1.5; }}
  .pane-error a {{ color:var(--ink); }}
  .pane-title {{ font-family:var(--font-display); font-size:var(--fs-md); font-weight:700; line-height:1.3;
    margin:0 0 var(--sp-8); color:var(--ink); }}
  .pane-byline {{ font-size:var(--fs-sm); color:var(--muted); margin-bottom:var(--sp-16); padding-bottom:var(--sp-12);
    border-bottom:var(--rule-hair); }}
  .pane-content {{ font-size:var(--fs-md); line-height:1.75; color:var(--ink); max-width:var(--measure); }}
  .pane-title, .pane-byline {{ max-width:var(--measure); }}
  .pane-content p {{ margin:0 0 1em; }}
  .pane-content h1,.pane-content h2,.pane-content h3,.pane-content h4 {{
    font-family:var(--font-display); margin:1.4em 0 .5em; line-height:1.25; }}
  .pane-content h1,.pane-content h2,.pane-content h3,.pane-content h4 {{ font-size:var(--fs-md); font-weight:700; }}
  .pane-content a {{ color:var(--ink); }}
  .pane-content img {{ max-width:100%; height:auto; border-radius:var(--radius-0); margin:var(--sp-8) 0; display:block; }}
  .pane-content figure {{ margin:1em 0; }}
  .pane-content figcaption {{ font-size:var(--fs-sm); color:var(--muted); margin-top:var(--sp-4); }}
  .pane-content blockquote {{ border-left:1px solid var(--rule); margin:1em 0;
    padding-left:var(--sp-12); color:var(--muted); font-style:italic; }}
  .pane-content pre {{ background:var(--paper); border-radius:var(--radius-0); padding:var(--sp-12); overflow-x:auto;
    font-size:var(--fs-sm); border:1px solid var(--rule); }}
  .pane-content code {{ background:var(--paper); border-radius:var(--radius-0); padding:var(--sp-4);
    font-size:var(--fs-sm); }}
  .pane-content pre code {{ background:none; padding:0; }}
  .pane-content ul,.pane-content ol {{ padding-left:var(--sp-24); margin:0 0 1em; }}
  .pane-content li {{ margin:.3em 0; }}
  .pane-content mark.hl {{ background:var(--highlight); color:inherit; border-radius:var(--radius-0); padding:0 var(--sp-4); }}
  /* highlight tooltip */
  .hl-tooltip {{ position:fixed; background:var(--sheet); color:var(--ink); border-radius:var(--radius-0);
    padding:var(--sp-4); z-index:200; box-shadow:0 0 32px var(--shadow); }}
  #hl-btn {{ background:transparent; border:0; color:var(--ink); cursor:pointer; font-weight:700;
    font-size:var(--fs-sm); padding:var(--sp-12); min-height:44px; white-space:nowrap; font-family:inherit;
    transition:background-color var(--dur-1) var(--ease-out),color var(--dur-1) var(--ease-out); }}
  #hl-btn:hover, #hl-btn:active {{ background:var(--ink); color:var(--paper); }}
  /* shortcuts dialog: level 2, a sheet with a shadow and no border */
  .kbd-overlay {{ position:fixed; inset:0; z-index:999; display:flex; align-items:center; justify-content:center;
    background:color-mix(in srgb, var(--paper) 72%, transparent); }}
  .kbd-box {{ background:var(--sheet); color:var(--ink); box-shadow:0 0 32px var(--shadow); padding:var(--sp-24);
    min-width:280px; max-width:calc(100vw - var(--sp-32)); max-height:calc(100vh - var(--sp-32)); overflow-y:auto; }}
  .kbd-head {{ display:flex; align-items:center; justify-content:space-between; gap:var(--sp-16); margin:0 0 var(--sp-12); }}
  .kbd-head h2 {{ margin:0; font-family:var(--font-display); font-size:var(--fs-md); font-weight:900; }}
  .kbd-close {{ font:inherit; font-size:var(--fs-sm); color:var(--ink); background:transparent; border:var(--rule-firm);
    border-radius:var(--radius-0); min-height:44px; min-width:44px; padding:var(--sp-8) var(--sp-12); cursor:pointer;
    transition:background-color var(--dur-1) var(--ease-out),color var(--dur-1) var(--ease-out); }}
  .kbd-close:hover, .kbd-close:active {{ background:var(--ink); color:var(--paper); }}
  .kbd-table {{ border-collapse:collapse; width:100%; }}
  .kbd-table th, .kbd-table td {{ padding:var(--sp-4) var(--sp-8); font-size:var(--fs-sm); text-align:left; vertical-align:top; }}
  .kbd-table th {{ font-weight:700; font-variant-numeric:tabular-nums; width:110px; }}
  .kbd-table td {{ font-weight:400; }}
  .kbd-note {{ margin:var(--sp-8) 0 0; font-size:var(--fs-sm); color:var(--muted); }}
  @media (max-width:900px) {{
    .reading-pane {{ width:100vw; }}
    body.pane-open .wrap {{ margin-right:0; }}
  }}
  /* ── keyboard focus: every interactive control gets a visible ring ─────── */
  a:focus-visible,
  button:focus-visible,
  summary:focus-visible,
  input:focus-visible,
  textarea:focus-visible,
  [tabindex]:focus-visible,
  [draggable="true"]:focus-visible {{
    outline:2px solid var(--anchor); outline-offset:2px; }}
  /* ── reduced motion: drop every transition and animation on request ────── */
  @media (prefers-reduced-motion: reduce) {{
    a, .title, .pill, #q, .ext-link, .ext-link:hover, .card-btn, .arc-pill, .note-trigger, .note-input,
    .drag-handle, .cluster:hover .drag-handle, #theme-btn, .pane-close, .pane-newtab, #hl-btn, .kbd-close,
    .item-head-main, .meta, .summary, .rbtl,
    .topic-ring .ring-fg, .cluster.focused > .item.lead, [data-tip]::after,
    .reading-pane, .reading-pane.open,
    .pane-loading {{ transition:none; animation:none; }}
    html {{ scroll-behavior:auto; }}
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
    <p class="mast-sub"><b>{stamp}</b><span>{len(items)} items live</span>
      <span>{new_count} new</span>
      <span class="mast-topics">AI, Design, AI×Design/Eng, Tech</span></p>
  </header>

  <div class="controls">
    <div class="pills-row">
      <button class="pill active" data-filter="all" aria-pressed="true">All</button>
      {pills}
    </div>
    <div class="search-row">
      <div class="search-field">{ICON_SEARCH}<input id="q" type="search" placeholder="Filter" autocomplete="off" aria-label="Filter stories"></div>
      <button id="rl-pill" class="arc-pill" aria-pressed="false">Saved</button>
      <button id="arc-pill" class="arc-pill" aria-pressed="false">Archive</button>
      <button id="theme-btn" title="Toggle dark mode">Dark</button>
      <button id="help-btn" class="arc-pill" data-tip="Keyboard shortcuts" aria-label="Help">?</button>
    </div>
  </div>

  <div class="no-results" id="no-results" hidden>
    <p id="no-results-msg">No stories match.</p>
    <button class="arc-pill" id="clear-filters" type="button">Clear filters</button>
  </div>
  <div class="front"><div class="front-grid{"" if insight_html else " solo"}">
    {insight_html}
    {whats_new}
  </div></div>
  {''.join(sections)}
  {refs_html}

  <footer class="foot">
    Generated by <code>/news-digest</code> on {run_date.isoformat()}. Persistent corpus:
    <code>corpus.json</code>; sources: <code>sources.json</code>. Items age out on a per-topic
    retention window; pinned items stay.
  </footer>
</div>

<div id="reading-pane" class="reading-pane" role="complementary" aria-label="Article reader">
  <div class="pane-toolbar">
    <span class="pane-site"></span>
    <div style="flex:1"></div>
    <a class="pane-newtab" target="_blank" rel="noopener" href="#" data-tip="Open in new tab" aria-label="Open in new tab">{ICON_EXT}</a>
    <button class="pane-close" data-tip="Close (Esc)" aria-label="Close reader">{ICON_CLOSE}</button>
  </div>
  <div class="pane-body">
    <div class="pane-loading" role="status">Loading…</div>
    <div class="pane-error" role="alert" style="display:none"></div>
    <h2 class="pane-title"></h2>
    <div class="pane-byline"></div>
    <div class="pane-content"></div>
  </div>
  <div class="hl-tooltip" id="hl-tooltip" style="display:none">
    <button id="hl-btn">Highlight</button>
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
  // Toggle buttons carry aria-pressed; the fill-weight icon replaces the bold one while on.
  const ICONS = {ICONS_JS};
  function setToggle(btn, kind, on) {{
    btn.setAttribute('aria-pressed', on ? 'true' : 'false');
    btn.classList.toggle('active', on);
    const want = on ? 1 : 0;
    if (btn.dataset.ico !== String(want)) {{ btn.innerHTML = ICONS[kind][want]; btn.dataset.ico = String(want); }}
  }}
  function syncClasses() {{
    document.querySelectorAll('.cluster[data-key]').forEach(cl => {{
      const k = cl.dataset.key;
      cl.classList.toggle('is-read', readSet.has(k));
      const rdBtn  = cl.querySelector('.read-btn');
      const rlBtn  = cl.querySelector('.rl-btn');
      const snzBtn = cl.querySelector('.snooze-btn');
      if (rdBtn)  setToggle(rdBtn,  'read',   readSet.has(k));
      if (rlBtn)  setToggle(rlBtn,  'rl',     readLater.has(k));
      if (snzBtn) setToggle(snzBtn, 'snooze', !!snoozed[k]);
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

      function setTrigger(t) {{ trigger.innerHTML = '{ICON_EDIT}' + '<span>' + t + '</span>'; }}
      function refresh() {{
        const saved = notes[k] || '';
        display.textContent = saved;
        display.classList.toggle('visible', !!saved);
        trigger.classList.toggle('has-note', !!saved);
        setTrigger(saved ? 'Edit note' : 'Add note');
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
        if (open) {{ ta.focus(); setTrigger('Cancel'); }}
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
    rlPill.setAttribute('aria-pressed',  viewMode === 'readlater' ? 'true' : 'false');
    arcPill.setAttribute('aria-pressed', viewMode === 'archive'   ? 'true' : 'false');
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
    const anyVisible = [...document.querySelectorAll('.cluster')].some(c => c.style.display !== 'none');
    document.getElementById('no-results').hidden = anyVisible;
    document.getElementById('no-results-msg').textContent =
      viewMode === 'archive' ? 'Nothing archived yet.'
      : viewMode === 'readlater' ? 'Nothing saved for later yet.'
      : 'No stories match' + (q.value.trim() ? ' "' + q.value.trim() + '".' : ' this filter.');
    updatePills();
    updateTopicRings();
  }}
  apply();
  function setActivePill(f) {{
    pills.forEach(x => {{
      const on = x.dataset.filter === f;
      x.classList.toggle('active', on);
      x.setAttribute('aria-pressed', on ? 'true' : 'false');
    }});
  }}
  document.getElementById('clear-filters').addEventListener('click', () => {{
    q.value = ''; active = 'all'; viewMode = 'normal';
    setActivePill('all');
    apply(); q.focus();
  }});

  pills.forEach(p => p.addEventListener('click', () => {{
    active = p.dataset.filter;
    setActivePill(active);
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
    // Enter on a focused button, link or summary activates it; it must not also open the focused story.
    if (e.key === 'Enter' && e.target.closest && e.target.closest('button,a,summary')) return;
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
  const SHORTCUTS = [
    ['j / ↓', 'Next card'], ['k / ↑', 'Previous card'], ['Enter / o / r', 'Open in reader pane'],
    ['m', 'Toggle read'], ['x', 'Archive'], ['s', 'Snooze until tomorrow'], ['b', 'Save for later'],
    ['n', 'Add / edit note'], ['/', 'Focus search'], ['?', 'This help'], ['Esc', 'Clear focus'],
  ];
  let kbdOpener = null;
  function closeShortcuts() {{
    const ov = document.getElementById('kbd-overlay');
    if (!ov) return;
    ov.remove();
    if (kbdOpener && document.contains(kbdOpener)) kbdOpener.focus();
    kbdOpener = null;
  }}
  function showShortcuts() {{
    if (document.getElementById('kbd-overlay')) {{ closeShortcuts(); return; }}
    kbdOpener = document.activeElement;
    const ov = document.createElement('div');
    ov.id = 'kbd-overlay';
    ov.className = 'kbd-overlay';
    const box = document.createElement('div');
    box.className = 'kbd-box';
    box.setAttribute('role', 'dialog');
    box.setAttribute('aria-modal', 'true');
    box.setAttribute('aria-labelledby', 'kbd-title');
    box.innerHTML = '<div class="kbd-head"><h2 id="kbd-title">Keyboard shortcuts</h2>' +
      '<button type="button" class="kbd-close">Close</button></div>' +
      '<table class="kbd-table">' +
      SHORTCUTS.map(r => '<tr><th scope="row">' + r[0] + '</th><td>' + r[1] + '</td></tr>').join('') +
      '</table><p class="kbd-note">Press ? or Esc to close</p>';
    ov.appendChild(box);
    ov.addEventListener('click', e => {{ if (e.target === ov) closeShortcuts(); }});
    box.querySelector('.kbd-close').addEventListener('click', closeShortcuts);
    ov.addEventListener('keydown', e => {{
      if (e.key === 'Tab') {{ e.preventDefault(); box.querySelector('.kbd-close').focus(); }}
    }});
    document.body.appendChild(ov);
    box.querySelector('.kbd-close').focus();
  }}

  // ── dark mode ─────────────────────────────────────────────────────────────
  (function() {{
    const osDark = window.matchMedia('(prefers-color-scheme: dark)');
    const saved = ls('digest-theme');
    // '' is what older builds stored for an explicit light choice.
    const chose = saved === 'dark' || saved === 'light' || saved === '';
    const dark = saved === 'dark' || (!chose && osDark.matches);
    document.documentElement.dataset.theme = dark ? 'dark' : 'light';
    themeBtn.textContent = dark ? 'Light' : 'Dark';
    osDark.addEventListener('change', e => {{
      if (ls('digest-theme') !== null) return;          // an explicit choice wins
      document.documentElement.dataset.theme = e.matches ? 'dark' : 'light';
      themeBtn.textContent = e.matches ? 'Light' : 'Dark';
    }});
  }})();
  themeBtn.addEventListener('click', () => {{
    const dark = document.documentElement.dataset.theme !== 'dark';
    document.documentElement.dataset.theme = dark ? 'dark' : 'light';
    themeBtn.textContent = dark ? 'Light' : 'Dark';
    localStorage.setItem('digest-theme', dark ? 'dark' : 'light');
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
      paneByline.textContent   = [data.byline, data.siteName].filter(Boolean).join(', ');
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
    if (e.key === 'Escape' && document.getElementById('kbd-overlay')) {{
      e.stopImmediatePropagation();
      closeShortcuts();
      return;
    }}
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
    ap.add_argument("--run-date", metavar="YYYY-MM-DD",
                    help="treat this date as today, so a committed corpus renders without the wall-clock prune")
    args = ap.parse_args()
    root = args.root

    corpus_path = os.path.join(root, "corpus.json")
    sources_path = os.path.join(root, "sources.json")
    corpus = load_json(corpus_path, {"items": [], "references": []})
    sources = load_json(sources_path, {})
    retention_cfg = sources.get("retention_days", corpus.get("retention_days",
                    {"default": 14, "design": 21, "ai_in_design": 30, "evergreen": 90}))

    run_date = dt.date.fromisoformat(args.run_date) if args.run_date else today()
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
