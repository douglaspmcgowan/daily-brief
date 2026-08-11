---
provenance: "douglas-core"
name: spec
description: "Write the WHAT for a build: one technology-agnostic SPEC.md carrying Product, Functional and machine-checkable Acceptance layers."
when_to_use: "Use when Douglas says write a spec, write the PRD, spec this out, what are the requirements for X, ground-truth doc for X, acceptance criteria for X, or invokes /spec. Produces the oracle the eval skills read -- user, probe, design-review, verify -- so reach for it before any of those. Grounded in IEEE 830 / ISO 29148, spec-kit, EARS requirement shapes, and ATDD acceptance-as-executable-spec. The technical HOW -- architecture, data model, contracts, tasks -- is out of scope and stays with writing-plans. Flags: --prd-only for the Product layer alone, --collaborate or --delegate for how ambiguity gets resolved."
---

# Spec

Invoke as `/spec [brief] [--prd-only] [--collaborate|--delegate]`.

A build with no written WHAT gets evaluated against whatever the last person remembered wanting. This command
produces the WHAT as a durable artifact: a single, technology-agnostic `SPEC.md` that says what the product is
for, what it must do, and — the load-bearing part — how anyone (a person or a downstream eval agent) proves it
is done. The three most-cited sources all merge the PRD and the functional spec into one document and draw the
real line at *what vs how* (Cagan: "PRD, Product Spec, or Functional Spec... describes functionality and
behavior, not how it will be implemented"; spec-kit's `spec.md`; Pocock's `to-spec`). This command is that
merged WHAT document, and nothing below it.

**The defining constraint** (the single fact that makes this behave differently from a default "write a spec"
pass): the `SPEC.md` it emits is *technology-agnostic* and its §Acceptance section is a *machine-consumable
oracle* — human-readable Given/When/Then co-located with a checkable grader, so the specification and the test
are one artifact and cannot drift (Adzic). It does not describe architecture, files, or code — that is the
plan's job, not the spec's. The oracle is also written to resist gaming: each grader asserts a property only
correct behavior produces, because any fixed check is a proxy and almost no proxy is unhackable (Skalse et al.;
Goodhart), and the eval agents that consume it are documented to hardcode outputs, delete assertions, or
monkey-patch the scorer to force a criterion green (EvilGenie; the specification-gaming literature).

**Deviation clause.** The staged procedure below is the well-reasoned default, not a straitjacket. When a
specific brief genuinely calls for a different move than the skill prescribes (a spec so small the gate should
route it away, a domain where the acceptance oracle needs a shape this doesn't cover), surface the divergence
and the reasoning to Douglas and let him decide — never silently comply, never silently go your own way.

## What this is NOT

- **Not `writing-plans`.** writing-plans owns the HOW — architecture, data model, API contracts,
  named seams, bite-sized TDD tasks with file paths. `/spec` owns the WHAT and stops at the tech-agnostic
  firewall: no file paths, no code, no stack choices in `SPEC.md`. The handoff is one-directional — the plan
  reads the spec; the spec never references the plan. `/spec` produces the oracle a plan is later built to satisfy.
- **Not `/design`.** `/design` is the full senior-designer arc (recon → concepts → interaction → build pathway
  → review). `/spec` is ONE artifact inside that arc: `/design` Step 3 calls `/spec --prd-only`, Step 5 calls
  `/spec`. Running `/design` should not also run `/spec` separately — Step 5 subsumes it. Run `/spec` standalone
  when you want the WHAT document without the whole design machine.
- **Not `brainstorming`.** Brainstorming explores intent conversationally before creative work.
  `/spec`'s grilling step (`--collaborate`) is a bounded, converging interview whose OUTPUT is a written spec,
  not open exploration. If a brief is genuinely unformed, brainstorm first, then `/spec` the result.
- **Not `/user` / `/probe` / `/design-review` / `/verify`.** Those CONSUME the spec — they read `SPEC.md#acceptance`
  as their ground-truth oracle and check a built product against it. `/spec` PRODUCES that oracle. It writes the
  claims; the eval skills prove them. `/spec` never runs the product or grades it.
- **Part of `/app-verification-chain`.** When the goal is to ship a whole app proven, `/spec` is Step 1 of that
  ordered gauntlet (it produces the `SPEC.md` oracle every later gate reads). Run `/spec` standalone for just the
  WHAT document; run `/app-verification-chain` to take an app end-to-end through spec → build → smoke → independent
  test → attack → structural guards → package.
- **Not a single merged spec+plan (the Pocock `to-spec` shape).** Pocock folds implementation decisions into
  one `to-spec` doc; spec-kit and this command keep the tech-agnostic WHAT (`SPEC.md`) firewalled from the
  technical HOW (the plan) so the acceptance oracle stays a clean, addressable, drift-free target for the eval
  pipeline. This is a deliberate divergence from Pocock, chosen for the multi-skill eval flow — stated so it's
  not mistaken for an oversight.

## Modes (flags)

- **`--prd-only`**: produce ONLY the §Product layer (the PRD content) and stop — problem, users, JTBD, success
  criteria, non-goals. Writes `SPEC.md` with §Product populated and §Functional/§Acceptance marked
  `PENDING — run /spec to complete`. This is what `/design` Step 3 calls; a later full `/spec` fills the same
  file in place (no second file, no drift).
- **`--collaborate`** (default when run standalone with an unformed brief): resolve ambiguity by **grilling** —
  Step 2 below. One question at a time, in dependency order, each carrying the recommended answer.
- **`--delegate`** (default when called from `/design --delegate`, or when the brief is already detailed):
  ask nothing; convert every ambiguity into a stated assumption marked `ASSUMED:` in the spec, so Douglas can
  veto later. Ambiguities that would waste >10 min if guessed wrong still get surfaced (his standing autonomy
  rule outranks this mode).

## Procedure

### Step 0 — Resolve the brief

Needs enough that the spec can be written without further context: what the product/feature is, who it's for,
and any prior art (a path to an existing README, `MAP.md`, or design doc, or a `--claims` source). If the ask names
an existing project, READ its current state first — a spec written over an inaccurate picture of what exists is
the first failure. If ARGUMENTS is too thin to know what's being specced and the conversation doesn't settle it,
ask what the thing is before proceeding. **Completion:** you can state, in one sentence, what product this spec
is for and who uses it.

### Step 1 — The gate (mandatory, before writing anything)

Stop conditions, checked honestly:
1. **Too small for a spec?** A one-line change or single-field tweak doesn't need a WHAT document — route it
   straight to the implementation skill (impeccable for UI, TDD for logic) and say so. A genuine feature is
   bigger than that.
2. **Already specced?** If a current `SPEC.md` (or equivalent) already answers §Product/§Functional/§Acceptance,
   don't re-derive it — validate it against the brief (Step 6's quality gate) and report, rather than
   overwriting a good spec.
3. **Not actually a spec problem?** "Make it faster" is `/hone`; "it's broken" is systematic-debugging;
   "review the built app" is `/design-review`. `/spec` writes the WHAT for something to be built or formalized.

**Completion:** you have explicitly cleared all three conditions, or routed the request elsewhere and stopped.

### Step 2 — Resolve ambiguity (grill, or assume)

Everything downstream inherits the ambiguity left here, so resolve it first — the way Pocock's grilling does.

**In `--collaborate`:** run a converging interview, not a firehose.
- **One question at a time**, in dependency order (model the open decisions as a tree — an early answer reshapes
  later questions; a bulk list destroys the structure that makes the interview converge).
- **Every question ships with your own recommended answer**, so Douglas reacts to a proposal instead of a blank
  prompt. Use AskUserQuestion with the recommended option first (his standing preference).
- **Anything the repo/brief can settle, read — don't ask.** Reserve questions for genuine judgment calls.
- **Gate:** do not start writing the spec until the shared understanding is confirmed.

**In `--delegate`:** convert each open decision into an `ASSUMED:` line in the spec instead of asking. Surface
only the ambiguities where a wrong guess wastes >10 min.

**Rule → example, both modes (Cucumber's example mapping).** Before closing this step, list the behavior
rules the brief implies and attach ONE concrete example (real values, context + expected result) to each. A
rule nobody can produce a concrete example for is unresolved ambiguity — it becomes a question (collaborate),
an `ASSUMED:` (delegate), or one of the markers below. These examples seed Step 5's scenarios directly.

**Bounded ambiguity, both modes.** Anything genuinely unresolved becomes an inline
`[NEEDS CLARIFICATION: <specific question>]` marker — **capped at 3 total**, prioritized
`scope > security/privacy > UX > technical detail` (spec-kit's cap). More than three unresolved blocking gaps
means the brief isn't ready for a spec — say so and grill/brainstorm first. **Completion:** every open decision
is either answered, `ASSUMED:`, or one of at most 3 `[NEEDS CLARIFICATION]` markers.

### Step 3 — Write §Product (the PRD layer)

The WHY, in Douglas's register (no antithesis constructions, per his voice rules). Problem before solution — the
single most consistent pattern across every product source (Lenny: "nailing the problem statement is the single
most important step"). Sections:
- **Root problem** — the problem *beneath* the request. A request for feature X usually names a symptom; state
  the problem Y underneath, because shipping X can pass while leaving Y untouched.
- **Users & context** — who uses this, expertise, environment. For Douglas's tools the honest persona is often
  "Douglas, expert, impatient, evaluating his own data" — write it anyway; it forces decisions (density over
  hand-holding, keyboard-first, no onboarding tours).
- **Jobs to be done** — the 3–6 jobs the user hires the product for, as ranked verbs.
- **Success criteria** — measurable and technology-agnostic **outcomes, not outputs** (Ulwick/JTBD). Each must
  survive the test: *measurable + controllable + solution-agnostic + tied to the job*. "Can go from schema edit
  to seeing new extraction output in under N seconds" passes; "ships the new editor UI" is an output and fails.
  Prefer percentiles over averages. ID each `SC-###`.
- **Non-goals** — what this deliberately will NOT do. The defining feature of a lean PRD and the cheapest scope
  control there is (Lenny highlights Kevin Yien's Non-Goals; Shape Up's "No-gos": "tells the team where to stop").
- **Constraints & assumptions** — platform, data, offline/online, and every `ASSUMED:` from Step 2.

`--prd-only` stops here (writes `SPEC.md` with §Functional/§Acceptance marked PENDING). **Completion:** §Product
has a root problem, ranked JTBD, ≥1 `SC-###` outcome metric that passes the outcome test, and an explicit
non-goals list.

### Step 4 — Write §Functional (the behavior layer) — technology-agnostic

The WHAT the system does, black-box, no implementation. spec-kit's proven skeleton:
- **Prioritized user stories P1/P2/P3...**, each **INDEPENDENTLY TESTABLE** — P1 alone must be a viable MVP
  slice (this is also the build order). Format: `As a <actor>, I want <capability>, so that <benefit>`. Each
  carries a one-line "Why this priority" and a one-line "Independent test."
- **Functional requirements** `FR-###` — zero-padded, RFC-2119 phrasing ("System MUST ..."), one testable
  capability each, stated separately (IEEE 830 "modifiable/traceable"). Phrase each in one of the five **EARS
  shapes** (Rolls-Royce's requirements syntax; how Kiro's `requirements.md` gets testable): ubiquitous
  ("The system MUST X"), event-driven ("WHEN <trigger>, the system MUST X"), state-driven ("WHILE <state>,
  the system MUST X"), unwanted-behavior ("IF <error/failure/bad input>, THEN the system MUST X"),
  optional-feature ("WHERE <feature is present>, the system MUST X"). An FR list that is all-ubiquitous is a
  coverage smell — the triggers, states, and failure responses went unspecced.
- **Key entities** (only if the feature involves data) — what each represents and its relationships, *without
  implementation* (domain model, not DB schema).
- **The firewall (enforced, not suggested):** NO language, framework, API, storage, or stack choice appears in
  §Functional. A tech noun here is a defect — it belongs in the plan. This is what keeps the spec stable and
  the acceptance oracle clean (spec-kit backs this with a checklist item, not a convention).

**Completion:** at least a P1 story that is a standalone MVP; every FR is a single testable MUST-statement; a
scan of §Product+§Functional finds zero implementation nouns.

### Step 5 — Write §Acceptance (the ground-truth oracle) — the load-bearing section

This is the section the eval skills consume, so it is *dual-layer, one artifact*: each criterion is
human-readable Given/When/Then AND carries a co-located machine-checkable grader. Rules:
- **Stable IDs** — each criterion `AC-###`, cited by any downstream eval verdict.
- **Traceable** — each AC names the story (P#) and the `FR-###`(s) it proves. Every P1 FR has ≥1 AC.
- **Binary** — no partial acceptance; a criterion is met or not (Segue: "There is no partial acceptance").
- **Given/When/Then**, declarative not imperative, one behavior per scenario, concrete example values (Cucumber
  "better Gherkin"). It must survive an implementation change — if the wording would change when the UI changes,
  rework it.
- **Measurable NFRs use the 4-part shape** — metric (a percentile, not an average) / threshold / condition /
  verification method. "95% of loads under 500ms at 1k concurrent, measured by synthetic tests," never "fast."
- **Every criterion names a verification method** — `Test | Demonstration | Inspection | Analysis` (ISO 29148).
- **Unhappy paths are mandatory** — every P1 story carries ≥1 negative AC (invalid input, failure, empty or
  limit state) where the expected error behavior IS the pass condition (Postman's negative-testing framing;
  ProductFTW: happy-path-only specs ship broken features). For each happy-path scenario ask "what could go
  wrong here?" and either write the AC or record in one line why nothing can.
- **The grader** binds the criterion to a checkable assertion (house schema below, trimmed from Microsoft waza):
  a `type` (`text | code | regex | prompt`), an optional `weight` (default 1.0 — load-bearing vs advisory), and
  a `config`. The grader is what lets `/user`/`/probe`/`/verify` mechanically decide pass/fail.
- **Ungameable graders** — a grader must fail unless the real work was done. Any fixed assertion is a proxy a
  capable agent can satisfy without meeting intent (Skalse et al.: almost no proxy is unhackable; Goodhart),
  and the eval agents downstream are documented to hardcode expected outputs, delete assertions, or patch the
  scorer to force a pass (EvilGenie; specification-gaming literature). Assert on a property only a correct
  implementation yields — a relationship, an invariant, a derived quantity — rather than one literal a stub can
  hardcode to. `len(result.mappings) == 3` alone is weak; pair it with a check that the mappings are the *right*
  ones. Several independent checks beat one; a lone literal-equality grader is a smell.

Emit §Acceptance as a fenced ```yaml block so it is machine-parseable (schema in the single-source section
below). **Completion:** every P1 FR has a traced, binary, GWT `AC-###` with a grader; every P1 story has ≥1
unhappy-path AC; every NFR criterion uses the 4-part shape; the YAML validates against the acceptance schema.

### Step 6 — Quality gate (grade the spec before writing it out)

Grade the drafted spec against the requirement-quality bar — this is the independent-validation discipline, and
in the Workflow it runs as a FRESH agent that did not write the spec (avoiding the coherence trap the way
`/probe`'s depth audit does). Check:
- **IEEE 830's characteristics of a good spec** — correct, unambiguous, complete (no unresolved TBDs beyond the
  ≤3 markers), consistent (no FR contradicts another, and one term means one thing throughout — inconsistent
  vocabulary for the same concept is an ISO 29148 requirements smell), ranked (P#/priority present), verifiable
  (every requirement has a verification method), modifiable (IDs + separate statements), traceable
  (FR→AC→SC links resolve).
- **SMART per requirement** — Specific, Measurable, Achievable, Relevant, Time-bound. A vague verb with no
  metric ("improve efficiency", "user-friendly"), an undefined adjective ("reasonable error handling"), or
  passive voice with no actor or deadline ("the system will be notified" — by what, within what?) is the tell
  of a non-testable requirement; flag and fix it.
- **Unhappy-path coverage** — every P1 story has ≥1 negative AC; an FR list with zero WHEN/WHILE/IF-THEN
  shapes means the triggers, states, and failure responses went unspecced. Flag and fix.
- **The firewall** — re-scan §Product+§Functional for implementation nouns; a tech leak is a defect.
- **Ungameable graders** — every load-bearing (weight ≥ 1.0) grader asserts a property only correct behavior
  produces. A criterion a stub could pass by hardcoding a literal, or that the eval agent could satisfy by
  patching the scorer, is flagged and hardened before ship (Goodhart; EvilGenie).
- **Acceptance-schema validation** — the ```yaml block parses and every AC has id/story/fr/given/when/then/grader.

Any failure is fixed inline before Step 7. **Completion:** every gate item passes or is explicitly recorded as
a known, scoped exception.

### Step 7 — Write the files + doc-rot discipline

- Write `SPEC.md` to the **project root**, next to `TASK.md`/`LOG.md` (the task-state convention in
  `AGENTS.md` → *Project startup and task state*). This said `STATUS.md` until 2026-08-08; that file is
  retired everywhere and must not be created, so following the old wording would have put a spec next to a
  file the harness forbids. One file — `--prd-only` writes the same file with only §Product filled.
- **No file paths or code snippets in the spec body** (Pocock: "They may end up being outdated very quickly").
  The one allowed exception is a snippet that encodes a decision more precisely than prose can.
- **Doc-rot header.** The spec is a planning artifact, and the code is the source of truth once it ships
  (Pocock). Write a status header at the top: `STATUS: draft | active | superseded`. When the build lands,
  whoever ships it marks the spec `superseded — see <review doc / MAP.md>`, so a later agent never treats a
  stale spec as authoritative and rebuilds against it. `/design` Step 9's "retire the planning artifacts" step
  is where this flips on ship.

**Completion:** `SPEC.md` exists at the project root with a STATUS header and the sections the mode requires.

### Step 8 — The honest final report

In the register of `/spar`/`/hone`/`/probe` (measured, non-fabricating):
- **What was produced** — which layers (§Product / §Functional / §Acceptance) got written this pass, and which
  are PENDING (e.g. after `--prd-only`).
- **Open decisions** — every `ASSUMED:` line and every `[NEEDS CLARIFICATION]` marker, surfaced so Douglas can
  veto or resolve. Never bury an assumption inside the file.
- **Quality-gate result** — which characteristics/SMART checks passed, and any known exceptions.
- **Traceability** — confirm every P1 FR has an AC and every AC traces to an FR; report any orphans.
- **Banned framings** — no "complete spec", "fully specified", "production-ready requirements". A spec is a
  draft claim until the code proves it; report what was written and what remains open.
- **The consumer handoff** — name that `SPEC.md#acceptance` is now available as the oracle for
  `/user --claims SPEC.md`, `/probe`, `/design-review`, `/verify`.
- Full absolute path of `SPEC.md`, per the standing Files-list convention.

## The acceptance block — single source of truth (schema + grader vocabulary)

§Acceptance is emitted as one ```yaml block. This is the ONLY place the format is defined; the eval skills parse
this shape. Schema (house schema, trimmed from Microsoft waza's `eval.yaml`):

```yaml
acceptance:
  - id: AC-001                 # stable, unique; cited by downstream eval verdicts
    story: P1                  # which user story this proves
    fr: [FR-001, FR-002]       # the functional requirement(s) it verifies (traceability)
    verification: Test         # Test | Demonstration | Inspection | Analysis  (ISO 29148)
    given: "a schema with 3 unmapped fields"
    when: "the user clicks Auto-map"
    then: "all 3 fields show a suggested mapping"
    grader:                    # binds the criterion to a checkable assertion
      type: code               # text | code | regex | prompt
      weight: 1.0              # optional; default 1.0 (load-bearing vs advisory)
      config:                  # shape depends on type (see below)
        assertions:
          - "len(result.mappings) == 3"
  # A measurable NFR criterion uses the 4-part shape instead of (or alongside) given/when/then:
  - id: AC-014
    story: P2
    fr: [FR-018]
    verification: Test
    measure:
      metric: p95_latency_ms   # a percentile, never an average
      threshold: 2000
      op: "<="                 # <= | < | >= | > | ==
      condition: "1000 concurrent users, EU region"
    grader:
      type: code
      config:
        assertions: ["p95(latencies) <= 2000"]
```

**Grader `type` vocabulary** (each returns `score` 0.0–1.0, `passed` boolean, `message`):
- `text` — `config.output_contains` (ALL must appear / AND) or `config.output_contains_any` (OR).
- `code` — `config.assertions`: a list of boolean expressions evaluated against the observed result/output.
- `regex` — `config.pattern`: a regex the output must match.
- `prompt` — `config.rubric`: a natural-language rubric an LLM-judge grades against (reserve for genuinely
  subjective criteria that no `text`/`code`/`regex` grader can pin down; a `prompt` grader on something
  mechanically checkable is a smell).

Required per criterion: `id`, `story`, `fr`, `verification`, `grader`, and either (`given`+`when`+`then`) or
`measure`. A criterion missing these fails Step 6's schema validation.

## Safety constraints

- Never run with elevated/bypass permissions. A blocked call means narrow scope, never route around it.
- `/spec` WRITES `SPEC.md` at the project root — a new file, or an in-place update of a `SPEC.md` this command
  owns. It never overwrites an authored doc of a different kind; if a `SPEC.md` exists that this command did not
  produce, back it up first (`_backups/SPEC.BACKUP_<ts>.md`) per the standing file-safety rule before rewriting.
- No commits or pushes unless Douglas separately asks.
- Research/grounding is open-web only for public/personal topics — NASA/CUI content never leaves the machine
  (block-nasa-web-egress enforces; don't test it).
- Surgical scope: write the spec the brief calls for, nothing speculative. No architecture, no code, no plan —
  those are `writing-plans`' job, and putting them here breaks the firewall this command exists to hold.

## Workflow script (optional — for an independent quality-gate validation pass)

The synthesis (Steps 2–5) runs INLINE in the calling session, because it needs the conversation context from
grilling and is Opus-judgment work. This Workflow is for the VALIDATION pass (Step 6) when you want a fresh
agent — one that did not write the spec — to grade it against the quality rubric, mirroring `/probe`'s
independent depth-audit so the grader can't rubber-stamp its own draft. Dispatch it after the spec is drafted;
skip it for a small `--prd-only` run.

```js
export const meta = {
  name: 'spec-validate',
  description: 'Independent quality-gate validation of a drafted SPEC.md against IEEE 830 / SMART / firewall / acceptance-schema, by a fresh agent that did not write it',
  phases: [
    { title: 'Validate' },
  ],
}

const SPEC_PATH = args.specPath            // absolute path to the drafted SPEC.md
const MODE = args.mode || 'full'           // 'full' | 'prd-only'

const VALIDATION_SCHEMA = {
  type: 'object',
  properties: {
    ieee830: {                             // one verdict per characteristic
      type: 'object',
      properties: {
        correct: { type: 'boolean' }, unambiguous: { type: 'boolean' }, complete: { type: 'boolean' },
        consistent: { type: 'boolean' }, ranked: { type: 'boolean' }, verifiable: { type: 'boolean' },
        modifiable: { type: 'boolean' }, traceable: { type: 'boolean' },
      },
      required: ['correct', 'unambiguous', 'complete', 'consistent', 'ranked', 'verifiable', 'modifiable', 'traceable'],
    },
    smart_violations: {                    // requirements that fail SMART, named
      type: 'array',
      items: { type: 'object', properties: { id: { type: 'string' }, why: { type: 'string' } }, required: ['id', 'why'] },
    },
    firewall_leaks: {                      // implementation nouns found in §Product/§Functional
      type: 'array',
      items: { type: 'object', properties: { location: { type: 'string' }, leak: { type: 'string' } }, required: ['location', 'leak'] },
    },
    acceptance_schema_valid: { type: 'boolean' },
    acceptance_schema_errors: { type: 'array', items: { type: 'string' } },
    traceability_orphans: { type: 'array', items: { type: 'string' } },   // FRs with no AC, ACs with no FR
    unhappy_path_gaps: { type: 'array', items: { type: 'string' } },      // P1 stories with no negative AC
    gameable_graders: { type: 'array', items: { type: 'string' } },       // ACs a stub could pass without doing the real work
    verdict: { type: 'string', enum: ['pass', 'fix_required'] },
    fixes: { type: 'array', items: { type: 'string' } },                  // actionable, per-issue
  },
  required: ['ieee830', 'acceptance_schema_valid', 'verdict'],
}

log(`Independent quality-gate validation of ${SPEC_PATH} (mode: ${MODE})`)
const result = await agent(
  `You did NOT write this spec — grade it skeptically, do not assume it is good. Read the file at ${SPEC_PATH} ` +
  `in full and grade it against the requirement-quality bar. MODE=${MODE} (if 'prd-only', §Functional/§Acceptance ` +
  `are expected to be PENDING — do not fault their absence, only grade §Product).\n\n` +
  `1. IEEE 830 characteristics — one boolean per: correct, unambiguous, complete (no TBD beyond the <=3 ` +
  `[NEEDS CLARIFICATION] markers), consistent (no FR contradicts another), ranked (P#/priority present), ` +
  `verifiable (every requirement names a verification method), modifiable (IDs + separately-stated), traceable ` +
  `(FR->AC->SC links resolve).\n` +
  `2. SMART — list every requirement that fails Specific/Measurable/Achievable/Relevant/Time-bound, with why ` +
  `(a vague verb with no metric is the tell).\n` +
  `3. Firewall — list any implementation noun (language/framework/API/storage/stack) appearing in §Product or ` +
  `§Functional; those belong in the plan, not the spec.\n` +
  `4. Acceptance schema — does the §Acceptance yaml block parse, and does every criterion have ` +
  `id/story/fr/verification/grader plus either given+when+then or measure? Report acceptance_schema_valid and ` +
  `any errors.\n` +
  `5. Traceability — name every FR with no AC and every AC with no FR (orphans).\n` +
  `6. Unhappy paths — name every P1 story with no negative AC (one where an expected error/edge behavior is ` +
  `the pass condition).\n` +
  `7. Gameable graders — name every AC whose grader a stub could pass WITHOUT doing the real work: a lone ` +
  `literal-equality assertion the code could hardcode to, or a check the eval agent could satisfy by patching ` +
  `the scorer. Any fixed check is a proxy and almost no proxy is unhackable (Goodhart; EvilGenie); a ` +
  `load-bearing grader must assert a property only correct behavior produces.\n\n` +
  `Return verdict 'pass' only if IEEE 830 is all-true, there are no firewall leaks, the acceptance schema is ` +
  `valid, there are no P1 traceability orphans, there are no P1 unhappy-path gaps, and no load-bearing grader ` +
  `is gameable. Otherwise 'fix_required' with a specific, actionable fix per issue.`,
  { phase: 'Validate', schema: VALIDATION_SCHEMA, label: 'spec-validate', model: 'opus' })

return result
```

