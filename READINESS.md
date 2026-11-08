# Readiness: daily-brief

| works | usable | polished | production | operated |
| --- | --- | --- | --- | --- |
| not-met | not-met | not-met (target) | not-targeted | not-targeted |

Target: polished

## Next gaps

- tests (failing): Test suite passes and runs at least one test.
- B1.1 (could-not-tell): Every core flow named in SPEC.md runs end to end.
- B1.3 (no-check): PRODUCT.md names who the app is for and why it exists.

## B1 Purpose and core flows

| item | statement | verify | state | last run |
| --- | --- | --- | --- | --- |
| B1.1 | Every core flow named in SPEC.md runs end to end. | agent | could-not-tell | 2026-11-08 |
| B1.2 | A fresh judge finds the app does what PRODUCT.md, SPEC.md and Douglas's asks say. | judge | could-not-tell | 2026-11-08 |
| B1.3 | PRODUCT.md names who the app is for and why it exists. | auto | no-check | never |

## B2 Feedback and response time

| item | statement | verify | state | last run |
| --- | --- | --- | --- | --- |
| B2.1 | A control reacts within 0.1 s. | agent | met | 2026-11-08 |
| B2.2 | Any wait over 1 s shows progress. | agent | met | 2026-11-08 |
| B2.3 | Work over 10 s can be left running or cancelled. | agent | met | 2026-11-08 |

## B3 States

| item | statement | verify | state | last run |
| --- | --- | --- | --- | --- |
| B3.1 | Every data region has loading, empty and error states. | auto | could-not-tell | 2026-11-08 |
| B3.3 | An empty state says what belongs there and offers one action. | judge | met | 2026-11-08 |

## B4 Errors and recovery

| item | statement | verify | state | last run |
| --- | --- | --- | --- | --- |
| B4.1 | No uncaught errors on the core flows. | auto | met | 2026-11-08 |
| B4.2 | An error message says what happened and what to do next. | judge | could-not-tell | 2026-11-08 |
| B4.3 | A failed action can be retried without retyping. | agent | could-not-tell | 2026-11-08 |

## B5 Data safety and undo

| item | statement | verify | state | last run |
| --- | --- | --- | --- | --- |
| B5.1 | Nothing typed is lost on reload, back or crash. | agent | met | 2026-11-08 |
| B5.2 | Reversible actions can be undone; only irreversible ones ask to confirm. | agent | failing | 2026-11-08 |

## B6 Navigation

| item | statement | verify | state | last run |
| --- | --- | --- | --- | --- |
| B6.1 | The user always knows where they are and how to get back. | judge | met | 2026-11-08 |
| B6.2 | Each view has its own URL and a unique title. | auto | no-check | never |
| B6.3 | Frequent actions have shortcuts. | agent | met | 2026-11-08 |

## B7 Accessibility to WCAG 2.2 AA

| item | statement | verify | state | last run |
| --- | --- | --- | --- | --- |
| B7.1 | Core flows work by keyboard alone, with visible focus. | auto | failing | 2026-11-08 |
| B7.2 | Text contrast is at least 4.5:1. | auto | met | 2026-11-08 |
| B7.3 | Large text and interface graphics contrast is at least 3:1. | auto | no-check | never |
| B7.4 | Zero axe violations at WCAG 2.2 AA. | auto | met | 2026-11-08 |
| B7.5 | Pointer targets are at least 24 px. | auto | no-check | never |
| B7.7 | Every non-text element has a text alternative. | auto | met | 2026-11-08 |

## B8 Layout from 320 px to 1440 px

| item | statement | verify | state | last run |
| --- | --- | --- | --- | --- |
| B8.1 | No horizontal scroll or clipped text at 320 px and 1440 px. | auto | met | 2026-11-08 |
| B8.2 | No horizontal scroll or clipped text at 768 px. | auto | met | 2026-11-08 |
| B8.3 | Layout holds at 200% text zoom. | auto | no-check | never |

## B9 Performance budgets

| item | statement | verify | state | last run |
| --- | --- | --- | --- | --- |
| B9.1 | Nothing jumps around after it loads. | agent | met | 2026-11-08 |

## B10 Error tracking and logs

| item | statement | verify | state | last run |
| --- | --- | --- | --- | --- |
| B10.1 | Uncaught errors are captured with the release, the route and the last action. | auto | failing | 2026-11-08 |

## B11 Security and privacy

| item | statement | verify | state | last run |
| --- | --- | --- | --- | --- |
| B11.1 | No secrets in the client bundle or the repository. | auto | no-check | never |

## B12 Onboarding and help

| item | statement | verify | state | last run |
| --- | --- | --- | --- | --- |
| B12.1 | A transient app is ready the moment it opens, with no setup step. | agent | met | 2026-11-08 |
| B12.3 | A first-time user reaches a useful result without help. | agent | met | 2026-11-08 |

## B13 Copy

| item | statement | verify | state | last run |
| --- | --- | --- | --- | --- |
| B13.1 | Copy is reread, with no machine vocabulary left. | judge | met | 2026-11-08 |

## B14 Visual design

| item | statement | verify | state | last run |
| --- | --- | --- | --- | --- |
| B14.1 | Visual design follows .agents/DESIGN.md and the project design language. | judge | met | 2026-11-08 |
| B14.2 | Every style comes from tokens, and dark mode reuses them. | auto | no-check | never |

## RD1 Finding and landing

| item | statement | verify | state | last run |
| --- | --- | --- | --- | --- |
| RD1.1 | A search result or in-site link opens at the heading it matched, not at the top of the page. | agent | met | 2026-11-08 |
| RD1.2 | At any scroll position the reader can see which section they are in, from a visible heading or a sticky section label. | agent | failing | 2026-11-08 |
| RD1.3 | No link has generic text alone, such as 'click here' or 'read more', and no link has an empty accessible name. | auto | no-check | never |
| RD1.4 | Each search result shows the title, a one-line summary and the section path, so the reader can choose without opening it. | judge | met | 2026-11-08 |

## RD2 Reading

| item | statement | verify | state | last run |
| --- | --- | --- | --- | --- |
| RD2.3 | Articles longer than one screen show reading progress that moves with the text the reader has reached. | agent | could-not-tell | 2026-11-08 |
| RD2.4 | On a long article, a control that returns to the top or to the contents is visible at the end without scrolling back. | agent | could-not-tell | 2026-11-08 |
| RD2.5 | Text size and theme choices persist across pages on the same site for the same reader. | judge | met | 2026-11-08 |

## RD3 Contents and search

| item | statement | verify | state | last run |
| --- | --- | --- | --- | --- |
| RD3.1 | The contents lists every level-2 and level-3 heading in the article, in document order, and marks the current section. | auto | no-check | never |
| RD3.3 | Each search snippet highlights the matched term. | auto | no-check | never |
| RD3.4 | The search field is labelled, and the result count is announced when it changes. | auto | no-check | never |

## RD4 Sharing, offline and print

| item | statement | verify | state | last run |
| --- | --- | --- | --- | --- |
| RD4.1 | A link to a section opens in a new tab at that heading. | agent | failing | 2026-11-08 |
| RD4.3 | Printed articles keep the article text, the last-updated date and each external link's address, and drop navigation, sticky headers, ads and banners. | judge | failing | 2026-11-08 |
| RD4.4 | Each article shows its last-updated date in its header. | auto | no-check | never |

## runtime Browser runtime errors

| item | statement | verify | state | last run |
| --- | --- | --- | --- | --- |
| S-WEB.1 | A window error listener is registered before app code runs, and each uncaught error it receives reaches the error sink. | agent | failing | 2026-11-08 |
| S-WEB.2 | An unhandled promise rejection has its own listener and reaches the error sink. | agent | failing | 2026-11-08 |
| S-WEB.3 | Each route sits inside an error boundary that shows that route's fallback and reports the caught error, and the other routes stay usable. | agent | failing | 2026-11-08 |
| S-WEB.4 | A chunk that fails to load after a deploy shows a reload prompt, not a blank page. | agent | could-not-tell | 2026-11-08 |

Generated from `.agents/work/readiness.json` by `Test-ProductReadiness.ps1 -Write`; do not edit. States derive from receipts.

`met` means the app's own command reported success. It does not mean the app is correct or good.

Kind: daily-brief | Generated: 2026-11-08T04:29:03.6959211Z | Input hash: 0a99347bb808

## Next (checks, detail)

Stage: works

- tests (failing): npm test - child exited 1

## Refresh

```powershell
& 'C:\Program Files\PowerShell\7\pwsh.exe' -NoProfile -NonInteractive -File ~/.agents/tools/Test-ProductReadiness.ps1 -ProductPath . -Profile .agents/app-profile.json -Check all -Write
```

## Stages (checks, detail)

| stage | state |
| --- | --- |
| works | not-met |
| usable | not-met |
| polished | partial |
| production | not-met |
| operated | met |

## Checks (detail)

### works

| check | state | last run | exit | note |
| --- | --- | --- | --- | --- |
| typecheck | met | 2026-11-08T04:27:58.4459703Z | 0 |  |
| tests | failing | 2026-11-08T04:28:23.4617488Z | 1 | child exited 1 |
| console-clean | met | 2026-11-08T04:28:28.4668817Z | 0 |  |

- build: package.json declares no build script; the app is build-free

### usable

| check | state | last run | exit | note |
| --- | --- | --- | --- | --- |
| loading-state | could-not-tell | 2026-11-08T04:28:30.0812715Z | 2 | \{"check":"loading-state","outcome":"could-not-tell","reason":"no .agents/app-selectors.json selector map","findings":\[\]\} |
| empty-state | could-not-tell | 2026-11-08T04:28:32.6971763Z | 2 | \{"check":"empty-state","outcome":"could-not-tell","reason":"no .agents/app-selectors.json selector map","findings":\[\]\} |
| error-state | could-not-tell | 2026-11-08T04:28:34.7269909Z | 2 | \{"check":"error-state","outcome":"could-not-tell","reason":"no .agents/app-selectors.json selector map","findings":\[\]\} |
| not-found-state | could-not-tell | 2026-11-08T04:28:36.3334994Z | 2 | \{"check":"not-found-state","outcome":"could-not-tell","reason":"no .agents/app-selectors.json selector map","findings":\[\]\} |
| keyboard-focus | failing | 2026-11-08T04:28:47.2056547Z | 1 | child exited 1 |
| error-capture | failing | 2026-11-08T04:28:49.3495259Z | 1 | child exited 1 |
| viewport-320-1280 | met | 2026-11-08T04:28:53.0855052Z | 0 |  |
| not-found-page | met | 2026-11-08T04:28:54.1171397Z | 0 |  |

Not applicable: structured-logs, cli-conformance, game-playable

### polished

| check | state | last run | exit | note |
| --- | --- | --- | --- | --- |
| design-banned-patterns | met | 2026-11-08T04:28:55.7136321Z | 0 |  |
| design-review-dated | never-run |  |  | no design-review receipt; run Write-DesignReviewReceipt.ps1 |

### production

| check | state | last run | exit | note |
| --- | --- | --- | --- | --- |
| seo-tags | failing | 2026-11-08T04:28:57.8717813Z | 1 | child exited 1 |
| axe | met | 2026-11-08T04:29:01.9485829Z | 0 |  |

Not applicable: privacy-terms, security-headers, core-web-vitals, log-personal-data

### operated

Not applicable: deployed-url, env-documented, monitoring, restore-path
