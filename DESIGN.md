# Project design rules

<!-- agent-harness:universal-design:v1:start -->
## Universal interface rules

The authority is `~/.agents/DESIGN.md`, and it is fuller than this. What follows is
carried here rather than only linked because a cloud or container session has no
`~/.agents` to reach — so the rules that actually change what gets built have to survive
in the repository itself.

### Anti-default discipline

Quoted verbatim from the authority rather than paraphrased, because this is the section an
agent most needs and a paraphrase is a second copy that drifts.

The model's house style is recognizable, and reaching for it reads as machine-made. Never
default to: purple-blue gradients, a centered hero over a dark mesh background, three equal
feature cards, ubiquitous glassmorphism, or Inter with slate everywhere. The
beige-brass-espresso "premium consumer" palette is the same tell; rotate off it.

- Lock one accent color page-wide, and one gray family per project.
- Lock one corner-radius system per page. Mix radii only under a rule you can state.
- Keep one theme per page. Sections do not invert light and dark mid-scroll except as a single deliberate composition device.
- A section layout family appears at most once per page. At most two consecutive image-text zigzag splits.
- **No eyebrow labels and no kicker titles on any page, deck, or artifact.** An eyebrow or kicker is the small uppercase or letter-spaced label above a heading; the heading carries its own weight, so delete the label. Ruled 2026-09-30.
- **Never use the middle dot `·` (U+00B7, `&middot;`) or the bullet `•` as an inline divider.** Separate inline items with a semicolon, `|`, a comma, or a line break. The em-dash stays banned as a divider. Ruled 2026-09-30.
- Where a brief reads as an established design system, use that system's official package rather than approximating it. One system per project.
- The brief wins. Honor a pinned aesthetic even when it is not the choice you would make; redirecting a clear brief toward your own taste is failure, not judgment.

### Names that appear here only to be forbidden

The rules above and below name specific typefaces in order to ban them. A project that
scans its own source for banned font names will find those names *here* and report this
file as the violation — measured on `base-flight-finder`, 2026-08-07, whose typography
policy test failed against text whose whole purpose is to forbid the thing it names.

**If you write such a scan, exclude the region between the two `agent-harness:universal-design`
marker comments.** That region is generated and is replaced wholesale on every sync, so
nothing a project owns ever lives inside it. The names are also declared machine-readably
on the next line, so a scanner can subtract them without parsing prose. `Test-DesignBlockScanSafety.ps1`
fails the build if any of them appears outside the markers, which is what makes the
exclusion sufficient rather than merely conventional.

**Match on word boundaries, not substrings.** `Inter` is a prefix of interaction,
interface, internal and interval, so a bare substring scan reports a violation on ordinary
English. That is a second, independent cause of the same false positive, and it lives on
your side of the line rather than in this block — the check above hit it on its own first
run, against the heading "Interaction and accessibility" a few sections down.

<!-- agent-harness:design-prohibited-names: IBM Plex Mono, Inter, Fraunces, Instrument Serif -->

### Everything else

- Never use IBM Plex Mono.
- **Never set anything in a monospace typeface unless it is code.** Not numbers, not labels, not reference tags, not captions, not credits, not timestamps. Monospace outside a code block is a costume that says "technical" and reads as machine output. Numerals that need to line up get `font-variant-numeric: tabular-nums` on the normal face instead.
- **Never use the middle dot as a separator.** No `·`, and no bullet character standing in for it. Separate with an en dash, a slash, a comma, or plain whitespace with a rule. The middle dot reads as machine-assembled metadata everywhere it appears, which is why it is out on every surface, not just decks.
- **Never write a line that is only "The" plus a noun.** "The transfer function", "The result", "The problem" — a bare definite noun phrase standing alone is the most common shape in machine-written copy and carries no more information than the noun alone. A title may open with "The"; a label, a bullet or a caption may not be one.
- **Never title anything as a noun followed by a rhythmic tag.** "The argument, rung by rung", "The story, piece by piece", "Design, from the ground up". The tag adds cadence, not meaning, and it is the tell that a title was composed rather than named. Title the thing by what it is.
- **A reference shown to a reader must be identifiable without the source document.** A bare bracket number or a bare superscript means nothing to someone who does not have the bibliography open, which on a slide or a poster is everyone. Name the author and year, and put the numbering in a source line if the numbering itself matters.
- Default to a sans display face. Use serif only with an articulated reason; `Fraunces` and `Instrument Serif` are banned as defaults specifically because they are the common machine-made choice.
- Hero discipline: the hero fits the first viewport, the headline runs at most two lines, subtext stays under roughly twenty words, and no more than four text elements sit inside it. Trust marks and logo walls go below the hero, never in it.
- A grid has exactly as many cells as there is content for. Reshape the grid rather than pasting in a blank tile.
- Every animation names what it communicates — hierarchy, sequence, feedback, or state change. An animation that names nothing gets cut.
- Reread every visible string before shipping. Never invent a precise-sounding number.
- Use a proportional body face for prose, navigation, labels, dates, names, and human-readable metadata.
- Reserve monospace for code and commands only, and set it in a code block. Identifiers, timestamps and numeric columns take the proportional face.
- Define explicit body and display roles, and a monospace role only where the surface actually renders code. Use tabular numerals on the proportional face for aligned quantities.
- Establish hierarchy through size, weight, spacing, and placement before decoration.
- **Use all-caps titles, labels, and headings very, very sparingly, only when absolutely necessary.** Uppercase letters and `text-transform: uppercase` both count; the default is sentence case. Ruled 2026-09-30.
- Give each screen a clear primary action or reading path. Use spacing and alignment to show relationships.
- Reuse existing tokens and components before adding variants.
- Cover relevant default, hover, focus, active, disabled, loading, empty, error, and success states.
- Use semantic structure and native controls, visible keyboard focus, logical tab order, accessible names, sufficient contrast, and non-color state cues.
- Support narrow, medium, and wide layouts, zoom, text resizing, touch targets, and reduced motion.
- A design skill's silence on accessibility is not an exemption. Seven of the sixteen design-adjacent skill packages carry no accessibility content at all, so the two bullets above are the floor whichever skill is driving.
- A visual world is chosen, not accumulated. Template packs, style presets, and named aesthetics contradict each other by construction — `retro-windows` bans every rounded corner where `capsule` requires a 9999px radius. Commit to one, take its taste entire, and treat the others as unread. The rules here apply to all of them.
- Inspect the existing design system, screenshots, and implementation before proposing a new rule or component.
- Verify browser-visible work with browser or end-to-end tests across responsive, keyboard, loading, empty, and error behavior.

### Design libraries

Concrete things to reach for — animation packages and working skeletons, icon kits, typeface pools, design-system install commands and canonical documentation. Read the leaf you need; each one loads on its own.

- **Index** `~/.agents/design/LIBRARIES.md`
- **Precedence and routing** `~/.agents/design/precedence.md` — which source wins when the universal rules, `impeccable` and a pinned brief disagree, and whether this project's design detector hook is actually wired
- **Stack templates** `~/.agents/design/STACK-TEMPLATES.md` — seven app-kind templates naming an occupant for all 22 stack slots, and the per-slot deviation rules. The selection itself belongs to `~/.agents/skills/stack/SKILL.md`: six observable questions, the scaffold, and `architecture.md`'s import direction. Enter there before choosing a framework, styling method, primitive layer or component source, and read the result in this file's `## Stack selection`; `solo-review` stack mode measures a real repository against it
- **Motion** `~/.agents/design/animation/` — `libraries.md`, `sticky-stack.md`, `horizontal-pan.md`, `scroll-reveal.md`, `liquid-glass.md` (frosted glass), `forbidden.md`
- **Icons** `~/.agents/design/icons/libraries.md`
- **Type** `~/.agents/design/type/families.md`
- **Design systems** `~/.agents/design/systems/install.md` and `sources.md`
- **Design languages** `~/.agents/design/languages/registry.md` — read it before committing a visual world or generating a new design language, and register the world committed for this project there in the same work unit
- **Surface craft** `~/.agents/design/craft/` — `high-end.md` (surface construction), `from-reference.md` (building faithfully from a reference image), `from-code.md` (reading a design system out of a live product's own CSS), `device-mockups.md`
- **Fundamentals** `~/.agents/design/fundamentals.md` — the arithmetic under a decision: palette construction (60-30-10, one accent, warm neutrals, the colourblind-safe sets and the grayscale test), type-scale ratios with a worked scale and measure, and grid selection. Read it when the palette or scale is not already decided
- **Slides and posters** `~/.agents/design/slides-and-posters.md` — the only leaf addressing a non-web medium: deck frameworks, PowerPoint craft, HTML deck frameworks, and the academic poster including A0 sizing and the ≥24pt body floor
- **Pre-ship matrix** `~/.agents/design/preflight.md` — the mechanical finish check for landing, marketing and portfolio surfaces; not dashboards, not product UI
- **Dashboards and data-dense product UI** `~/.agents/design/dashboards.md` — the full system for the surface this tree used to leave uncovered: the three dashboard kinds and why building one while thinking of another causes most of the mistakes, information architecture and the three reading distances, density targets set against marketing spacing, typography and colour for data (sequential, diverging, categorical and semantic scales), chart selection ordered by the Cleveland-McGill perceptual ranking, chart and table craft, the six states every data region has, filters and URL state, interaction, real-time cadence, renderer choice by point count, the charting-library table, the anti-patterns, and a §18 pre-ship matrix that is the entry above's equivalent for this medium. This line used to say the tree did not own dashboards and pointed at the `/design-review` rubric, which critiques a running app rather than generating one; that gap closed on 2026-08-09
- **Mobile, touch and responsive** `~/.agents/design/mobile.md` — the medium, not a surface type: the three kinds of mobile thing and why a responsive site should not get a bottom tab bar, the viewport and its moving parts (`svh`/`lvh`/`dvh`, `viewport-fit=cover`, `env(safe-area-inset-*)` with the `max()` fallback that is the part people omit), the three touch-target floors — WCAG 2.2's 24px, Material's 48dp, Apple's 44pt — and which to design to, thumb reach and what it decides, mobile type including the 16px threshold below which iOS zooms a focused input, breakpoints and container queries, navigation patterns, forms with `inputmode`/`autocomplete`/`enterkeyhint` and the keyboard that covers your action bar, the gestures the OS has already reserved, the states that do not exist without a pointer, scrolling, the motion budget on a mid-tier device, images, offline, touch accessibility, the anti-patterns, a §18 pre-ship matrix, and §19 on the four checks emulation cannot answer. It does not restate `impeccable`'s `reference/adapt.md`, which owns converting an existing surface between contexts
- **Production readiness** `~/.agents/design/ADVISOR-PRODUCTION-READY.md` — what still stands between the design-space explorer and the Work Scope graph and real use
- **Design-space explorer** `~/.agents/design/design-space-explorer/README.md` — the reusable two-axis combination explorer, its intent, specification, design rules, and inspection record
- **Design-space manifests** `~/.agents/design/design-spaces/README.md` — the reusable schema for design-space axes, entries, palettes, templates, and generated-axis sources
- **Mission-control design studies** `~/.agents/design/mission-control/AESTHETIC-OPTIONS.md` and `REPRESENTATIONS.md` — visual-world and information-representation options for that surface

The full universal rules are `~/.agents/DESIGN.md`. Where a library entry and a rule disagree, the rule wins.

**This list is enumerated because it has to be.** A cloud or container session has no `~/.agents` to walk, so this block is the only routing it gets — which also means a leaf missing here is a leaf that session cannot reach at all. `craft/` and `preflight.md` were absent until 2026-08-07 and every project copy inherited the gap. `Test-DesignLibraryIndex.ps1` now fails the build when this list falls behind the tree.
<!-- agent-harness:universal-design:v1:end -->

## Design system: Ledger, as built for a personal news digest

Decided 2026-10-04. This is the **extend** case: the committed identity (warm paper and ink, one
brick anchor, a serif masthead, a real dark counterpart) is good and is kept. What was missing was a
system around it, so the page read as tinted rounded cards and outlined pills. Ledger supplies the
system: a working broadsheet with a masthead, rules instead of boxes, square corners and a firm
measure.

- **Direction:** Ledger, "print discipline for a screen-only world".
- **Pulled from:** hue seventeen, `~/.agents/skills/hue/examples/ledger/design-model.yaml` and its
  rendered `landing-page.html`; the same world is rendered at
  `C:/Users/dougl/Projects/design-worlds/worlds/ledger/` (`index.html`, `spec.html`). Roster entry:
  `~/.agents/design/languages/registry.md`, row Ledger.
- **Taken from Ledger:** the type pair, square corners, double and hairline rules as the only
  dividers, the typographic masthead, bold Phosphor icons used as punctuation, and near-zero motion.
- **Not taken, and why:** Ledger's cream stock and press red (the audit of 2026-09-27 lists
  recolouring as not recommended, so this project's paper, ink and brick stay); its kicker eyebrows,
  uppercase labels and middle-dot datelines (universal rules ban all three); its third sans face for
  labels (two families are enough here, and that face is a banned default); its 128px hero (this is
  a tool opened daily, not a landing page).
- **Wrong if:** the digest becomes a feed checked many times a day. A broadsheet is a once-a-day
  object.

Every rule below lives in `build_digest.py`: the `<style>` f-string and its token constants.
`index.html` and `digest.html` are generated output; editing them directly is a defect.

### Stack selection

No framework, and none is added: a Python 3.13 script emits one self-contained static page with
inline CSS and vanilla JavaScript, served by Vercel beside one function (`api/reader.js`). The
system is inline custom properties plus hand-written CSS. No component library, no CSS framework,
no build tool. Ledger is a hue example world, not a published package, so there is no official
package to install; the two typefaces and the icon kit come from their own official sources below.

### Colour

Nine colours per mode, all tokens on `:root`, plus one shadow alpha. Surface levels are named.
Contrast figures were computed with the WCAG formula on 2026-10-04.

| Token | Role | Light | Dark |
|---|---|---|---|
| `--paper` | surface level 0, the page | `#f6f3ec` | `#1c1914` |
| `--sheet` | surface level 1: input, reader pane, tooltip, dialog (renames `--card`) | `#fffdf8` | `#252017` |
| `--ink` | text, firm rules, control borders, active fills | `#1d1a16` | `#ede9e0` |
| `--muted` | metadata, sources, dates | `#6b6357` | `#9a9088` |
| `--rule` | hairline between stories and list rows | `#e3ddd0` | `#3b342a` |
| `--anchor` | brick: masthead accent word, focus ring, progress ring, marks | `#c8482b` | `#e06750` |
| `--anchor-deep` | brick as small text, and the fill behind the New badge | `#a8391f` | `#e06750` |
| `--highlight` | the reader's own text highlight | `#fff176` | `#4a3d00` |
| `--caution` | see status tokens | `#7a5c00` | `#d9b64a` |
| `--shadow` | overlay shadow, ink at alpha | `rgba(29,26,22,.14)` | `rgba(0,0,0,.5)` |

Measured pairs: ink on paper 15.64, ink on sheet 17.05, muted on paper 5.34, muted on sheet 5.82,
anchor-deep on paper 5.80, paper on anchor-deep 5.80, caution on paper 5.64; dark: ink on paper
14.46, muted on paper 5.61, muted on sheet 5.18, anchor on paper 5.19, anchor on sheet 4.80,
caution on sheet 8.28. `--anchor` on paper is 4.29, so in light mode it never carries text smaller
than the masthead; small brick text takes `--anchor-deep`.

Status tokens are separate names so a status can be retuned without touching the brand:

| Token | Meaning | Value | Non-colour cue |
|---|---|---|---|
| `--status-new` | first seen since the last digest | `var(--anchor-deep)` | the word New in a filled square badge |
| `--status-error` | reader could not fetch, generic failure | `var(--anchor-deep)` | message text plus a link to the original |
| `--status-caution` | snoozed, stale corpus notice | `var(--caution)` | fill-weight moon icon, `aria-pressed` |
| `--status-done` | read | `var(--muted)` | fill-weight check icon, story dims to 55% |
| `--status-saved` | saved to the reading list | `var(--ink)` | fill-weight bookmark, `aria-pressed` |

Retired by this system: `--link` (links are ink with a 1px underline, brick on hover; a paper has no
blue), `--ink-soft` (prose is `--ink`), `--anchor-soft` (no tinted callouts), `--on-anchor` (text on
brick is `--paper` on `--anchor-deep`), `--warn` (`#b8960c` measured 2.56 on paper; replaced by
`--caution`), `--shadow-firm` (one shadow token).

### Type

Two families, both open licence (SIL OFL) from Google Fonts. The serif is justified: the product is
a newspaper, and this is Ledger's own pair.

- **Display: Playfair Display**, weights 700 and 900, italic 700. Roles: masthead, topic heads,
  story titles, the reader pane's article title.
- **Body: PT Serif**, weights 400 and 700, italic 400. Roles: prose, metadata, controls, labels,
  dates, counts (with `font-variant-numeric: tabular-nums`). Italic 400 sets sources and the
  editor's sidebar.
- **Code:** none. The page renders no code; `code` and `pre` inside fetched articles fall back to
  the user agent's monospace and nothing else is set in it.
- **Loading:** one stylesheet link,
  `https://fonts.googleapis.com/css2?family=Playfair+Display:ital,wght@0,700;0,900;1,700&family=PT+Serif:ital,wght@0,400;0,700;1,400&display=swap`,
  with `preconnect` to `fonts.googleapis.com` and `fonts.gstatic.com`. Fallback stacks keep the page
  whole offline: `--font-display: "Playfair Display", Georgia, "Times New Roman", serif` and
  `--font-body: "PT Serif", Georgia, "Iowan Old Style", serif`.
- **Scale:** ratio 1.25 on a 17px base. Three sizes, which is also the per-screen ceiling.

| Token | Step | Value | Used by |
|---|---|---|---|
| `--fs-sm` | -1 | `0.85rem` (13.6px) | metadata, controls, labels, counts |
| `--fs-md` | 0 | `1.0625rem` (17px) | prose, story titles, topic heads, reader text |
| `--fs-display` | +5, fluid | `clamp(2.125rem, 6vw + 0.75rem, 3.25rem)` (34px to 52px) | the masthead only |

- The display floor is 34px, exactly twice the body, so the largest heading never drops under 2x.
- Weights: 400, 700, 900. 900 belongs to the masthead and topic heads. Never 500 or 600.
- Leading: display 1.0, titles 1.25, prose 1.6, metadata 1.45. Masthead tracking `-0.02em`.
- Hierarchy among 17px text comes from face (Playfair against PT Serif), weight and rules, never
  from a fourth size. Reader-pane article headings are forced to `--fs-md`.
- Measure: `--measure: 68ch`. Summaries, the between-the-lines block and reader prose never run
  wider. Prose stays `--fs-md` at every width, including 375.
- No uppercase, no eyebrow labels, no middle dot. Inline items are separated by `|` (in an
  `aria-hidden` span), a comma, or a gap.

### Spacing, radii, rules, elevation

- **Spacing:** `--sp-4 --sp-8 --sp-12 --sp-16 --sp-24 --sp-32 --sp-48 --sp-64`. Every margin, padding
  and gap takes one. The reader pane's article body keeps `em` rhythm because it styles third-party
  markup. Section padding and the page gutter use `clamp()` over these tokens.
- **Radii:** one value, `--radius-0: 0`. Square corners on every control, badge, input, pane and
  image. The progress ring is a drawn circle, not a radius. The ten numbered radius tokens,
  `--radius-round` and `--radius-pill` are deleted.
- **Rules** are the system's dividers and its only decoration:
  `--rule-hair: 1px solid var(--rule)` between stories and list rows;
  `--rule-firm: 1px solid var(--ink)` around controls and under the sticky bar;
  `--rule-double: 4px double var(--ink)` under the masthead and above each topic head.
  No coloured side bar wider than 1px anywhere; the reader blockquote keeps a 1px left hairline.
- **Elevation**, declared once per surface, never a rule and a shadow together:
  level 0, paper, flat; level 1, in-flow sheet (search field, note area), `--rule-firm` border, no
  shadow; level 2, overlay (reader pane, highlight tooltip, shortcuts dialog), `--sheet` with
  `box-shadow: 0 0 32px var(--shadow)` and no border.

### Motion tokens

- `--ease-out: cubic-bezier(.22,1,.36,1)` for anything entering or responding.
- `--ease-in: cubic-bezier(.4,0,1,1)` for anything leaving.
- `--dur-1: 120ms` feedback; `--dur-2: 200ms` state change; `--dur-3: 320ms` an overlay arriving.
- No transition names `linear`, `ease` or `ease-in-out`, and none carries a literal duration.

### Icons

Phosphor, bold weight for the resting state and fill weight for a toggled-on state, MIT licence.
Inline SVG, because the page is one self-contained file: path data is copied unmodified from
`@phosphor-icons/core` (`https://unpkg.com/@phosphor-icons/core@2.1.1/assets/bold/<name>-bold.svg`
and `/assets/fill/<name>-fill.svg`) into the `ICON_*` constants, `viewBox="0 0 256 256"`,
`fill="currentColor"`, sized `1.15em`. One family; no hand-drawn paths. Icon-only controls carry an
`aria-label`.

| Constant | Phosphor name | Where |
|---|---|---|
| `ICON_EXT` | `arrow-up-right` | open the original |
| `ICON_CHECK` | `check` (bold), `check-circle` (fill, when read) | mark read |
| `ICON_BOOKMARK` | `bookmark-simple` | save |
| `ICON_SNOOZE` | `moon` | snooze |
| `ICON_ARCHIVE` | `archive` | archive, dismiss |
| `ICON_EDIT` | `pencil-simple` | add note |
| `ICON_CLOSE` | `x` | close pane, close dialog |
| `ICON_STAR` | `star` (fill) | pinned |
| `ICON_GRIP` | `dots-six-vertical` | drag handle |
| `ICON_SEARCH` | `magnifying-glass` | leading mark in the search field |

### Components and states

Every interactive control exists today and stays. Shared states for all of them: default; hover
(colours invert toward ink through `--dur-1`); focus-visible
(`outline: 2px solid var(--anchor); outline-offset: 2px`, the only focus treatment); active (pressed
fill held for the press); disabled (`opacity: .45`, `cursor: not-allowed`, no hover response,
`aria-disabled` or `disabled`). Every control box is at least 44 by 44 CSS px with 8px between
neighbours.

| Component | Selector | Form | States beyond the shared set |
|---|---|---|---|
| Masthead | `header.mast`, `.mast-title`, `.mast-sub` | logo mark, title in Playfair 900 with the word Daily in `--anchor`, date line, `--rule-double` beneath | none; static. The one `h1` |
| Section index | `.pill` in `.pills-row` | square text tabs with a tabular count, `--rule-firm` border | selected: ink fill, paper text, `aria-pressed="true"`; zero-count: muted, still pressable |
| Search field | `#q` | level 1 sheet, firm border, leading search icon, `/` focuses | filled; focus; no-match drives the empty state |
| View toggles | `#rl-pill`, `#arc-pill` | square text buttons | on: ink fill, `aria-pressed` |
| Theme button | `#theme-btn` | square text button naming the mode it switches to | resolves the OS preference on load; an explicit choice persists in `localStorage['digest-theme']` |
| Help button and shortcuts dialog | `#help-btn`, `#kbd-overlay` | square `?` button; level 2 dialog, key and action list in PT Serif | open, closed; Escape and a Close button dismiss; focus returns to the button |
| Editor's sidebar | `.insight-card` | no fill, no radius: `--rule-double` above, hairline below, quote in PT Serif italic, source line in `--fs-sm` | empty: the block is not rendered |
| Front-page index | `.whatsnew` | numbered list on paper, rows split by hairlines, title 700, source in muted italic | empty: one line, "Nothing new since the last digest." |
| Topic head | `.topic-h`, `.topic-progress` | Playfair 900 at `--fs-md` under `--rule-double`, count and read progress ring at the right | empty lane: says so inline; complete: ring closed |
| Story | `.cluster`, `.item` | unboxed article between hairlines: title, meta, summary, between-the-lines | new (badge); read (55% opacity, check filled); saved; snoozed; pinned (star); keyboard-current (firm rule above replaces the hairline); dragging |
| Between the lines | `.rbtl` | run-in bold lead in `--anchor-deep`, then PT Serif italic, within the measure | absent when the item has none |
| Story actions | `.card-btn` (`.read-btn`, `.rl-btn`, `.snooze-btn`, `.dismiss-btn`), `.ext-link` | 44px square icon buttons, no border at rest, tooltip from `data-tip` | toggled: fill-weight icon, `aria-pressed="true"`; hover: firm border |
| Drag handle | `.drag-handle` | grip icon in the left gutter | visible on hover and focus, always visible on touch |
| Note | `.note-area` and its Add note button | text button; opens a level 1 sheet textarea | empty, has-note, editing, saved |
| More on this story | `.also-wrap` `details` | native disclosure, list of sources | open, closed |
| Reference list | `.references`, `.ref-list` | hairline-separated links in CSS columns | empty: section not rendered |
| Reader pane | `.reading-pane` and `.pane-*` | level 2 overlay at the right, toolbar with site name, new-tab and close | closed; loading (pulsing line); loaded; error (message in `--status-error` with a link to the original) |
| Highlight tooltip | `.hl-tooltip`, `#hl-btn` | level 2 chip above a text selection in the reader | hidden, shown; highlighted text takes `--highlight` |
| Empty state | `#no-results` | reason line plus a Clear filters button | names which of filter, search, Saved or Archive is empty |
| Footer | `.foot` | hairline above, muted `--fs-sm` | none |

### Layout grid

One centred column, `--wrap: 70rem` (1120px), gutter `clamp(var(--sp-16), 4vw, var(--sp-24))`.
Components size themselves from their container, not the viewport: `.cluster` and the front page
are `container-type: inline-size`.

- **Story grid.** When its container is 800px or wider: two columns,
  `minmax(0, var(--measure)) minmax(12rem, 1fr)` with a `--sp-48` gap. Title, summary and
  between-the-lines sit in the text column; source, date, type and the action buttons sit in the
  meta rail, top-aligned. Narrower than 800px: one column, meta as one wrapping line under the
  title, actions in a row beneath the text.
- **Front page.** When its container is 800px or wider: `minmax(0, 2fr) minmax(0, 1fr)` with the
  front-page index left and the editor's sidebar right. Narrower: stacked, sidebar first.
- **1440:** the wrap sits at 1120px with the story grid in two columns; text measures 68ch and the
  rail takes the remainder. References in three columns with hairline column rules. With the reader
  pane open (40vw) the wrap narrows under 800px and stories fall to one column by container query.
- **768:** stories in one column at the full content width, prose still capped at 68ch; front page
  stacked; references in two columns; controls wrap onto two rows.
- **375:** one column, 16px gutter; the section index scrolls sideways inside its own box and the
  page never does; the search field takes a full row; references in one column; the reader pane is
  full-width.
- The sticky controls bar holds `--paper` and a `--rule-firm` bottom edge. No horizontal page scroll
  and no clipped text at any of the three widths.

### Motion inventory

It is a paper; motion only answers the reader. Each entry names what it communicates.

| Motion | Tokens | Communicates |
|---|---|---|
| Control hover and press: colour and background | `--dur-1`, `--ease-out` | feedback: this responds to you |
| Toggle on or off (read, save, snooze, section tab) | `--dur-1`, `--ease-out` | state change |
| Story dims when marked read | opacity, `--dur-2`, `--ease-out` | state change: this one is done |
| Progress ring advances | `stroke-dashoffset`, `--dur-3`, `--ease-out` | progress through the lane |
| Jump from the front-page index: the target story flashes `--highlight` and fades | background, `--dur-3`, `--ease-out` | orientation: this is where you landed |
| Reader pane arrives from the right edge | `translateX(16px)` and opacity, `--dur-3`, `--ease-out`; leaves on `--dur-2`, `--ease-in` | sequence and origin: a second sheet laid beside the page |
| Reader loading pulse (the one `@keyframes`) | opacity, 1.4s | loading: the fetch is still running |
| Tooltip and drag handle appear | opacity, `--dur-1` | feedback on hover or focus |

Nothing animates on scroll, on load or on filter change. `prefers-reduced-motion: reduce` zeroes
every transition and the keyframes through a matching-specificity selector list, without
`!important`.

### Dark mode

The same tokens redefined, values in the colour table: under `html[data-theme="dark"]` and under
`@media (prefers-color-scheme: dark) :root:not([data-theme="light"])`. `body` carries an explicit
`background: var(--paper)`. No component has a dark override; `theme-color` is set for both modes.

### Formats

- **Masthead date:** weekday, month, day, year, no leading zero: `Monday, June 5, 2026`.
- **Story age:** `today`, `yesterday`, `3d ago` for two to seven days, then abbreviated month and
  day with no year: `Jun 7`.
- **Counts:** integers with a comma at thousands, tabular numerals, the unit as a word:
  `111 items live`, `13 new`. Section tabs show the bare count.
- **Progress:** read over total with a slash and no spaces: `1/32`.
- **Ranges:** en dash, no spaces: `June 13–15`.
- **Units:** days abbreviate to `d` only in story age; nothing else abbreviates. No times of day are
  shown; if one is added it is 12-hour with lowercase `am` or `pm` in the reader's local zone.
- **Sources:** publication, then a slash and the organisation when both exist: `TLDR AI / Anthropic`.

### Interaction and accessibility

- One focus ring on every control, as above. `!important` is not used.
- Every text colour clears WCAG AA on its own background; control boundaries are `--ink`, which
  clears 3:1 on both surfaces (the old `--rule` control borders measured 1.22 on paper).
- `tests/floor.spec.js` asserts zero serious or critical `axe` violations, no sideways scroll at
  375, 768 and 1440, 44px targets, at most three font sizes, one `h1`, the head tags, the empty
  state, and no middle dot, uppercase or monospace in chrome. It stays green through every packet.
- Head: unique `<title>`, favicon, `theme-color` (light and dark), `og:title`, `og:description`,
  `og:image` (`/og-image.png`, 1200 by 630).
- Keyboard: every shortcut in the shortcuts dialog keeps working; the reader pane closes on Escape.

### Recorded exceptions

- **Serif display and serif body.** The universal default is a sans display face. This is a
  newspaper and the system is Ledger, whose pair is Playfair Display and PT Serif.
- **Shadow alpha beside nine colours.** `--shadow` is ink at alpha for the three overlays, not a
  tenth hue.
- **Web fonts from a third-party host.** The page was self-contained; it now makes one font request
  and falls back to Georgia without it. Self-hosting is on the later list.
- **Marketing-buzzword detector hit.** "Best-in-class" in the reference list is a note stored in
  `corpus.json` for a third-party source; content, not product copy.
- **`og:image` is root-relative.** No deploy domain is recorded (`vercel.json` names none). Set the
  absolute URL when one exists.
- **Reader blockquote left hairline.** 1px, on a blockquote, in third-party article markup; the
  detector's side-tab check reads it as an accent bar and it is not one.
- **`em` rhythm inside `.pane-content`.** It styles markup this project does not author.

### Recommendations

In this build:

1. Load Playfair Display and PT Serif; retire Georgia and the system sans as primary faces.
2. Re-base the three-size scale on 17px at ratio 1.25, with a 34px display floor.
3. Trim the palette to nine tokens: retire the link blue, the tinted anchor wash and the soft ink;
   replace the 2.56:1 warn colour with `--caution`; add the five status tokens.
4. Collapse eleven radii, the pill and the round to square corners.
5. Add `--rule-hair`, `--rule-firm`, `--rule-double`, `--dur-1` to `--dur-3`, `--ease-in`, `--wrap`,
   `--measure`.
6. Replace the hand-drawn icons with Phosphor bold and fill, and add a search icon.
7. Turn the outlined pills into a square section index; give every control ink borders.
8. Unbox the story: hairlines between articles, a 68ch text column and a meta rail by container
   query.
9. New layout: a front page that sets the new-since index beside the editor's sidebar.
10. Double-rule topic heads; the insight block and the new-since block lose their tint, gradient
    and radius.
11. One new animation: the reader pane arriving from the right edge.
12. A `--run-date` argument on `build_digest.py`, so the page can be regenerated from the committed
    corpus without the wall-clock prune emptying it.

Proposed for later:

1. Collapse stories to title and meta by default, expanding on demand. The page measured 21,370px
   tall at 1440 with 80 stories. It changes what the app is on first open, so it needs Douglas.
2. Self-host both faces as `woff2` under `/fonts/` so the page is self-contained again.
3. A print stylesheet: a broadsheet should print as one, in two columns with the controls removed.
4. An edition number in the masthead, counted from `digests/`.
5. A lead story at 1440: the first new item set across the full measure with a larger rail.
6. Ledger's halftone dot field behind the masthead only, ink at about 3.5% alpha.
7. Redraw `og-image.png` in the new faces.
8. Register this world in `~/.agents/design/languages/registry.md` as a Ledger variant; that file is
   outside this repository.
9. Fill `PRODUCT.md`; it is an empty template, and there is no `INTENT.md` or `SPEC.md`.
