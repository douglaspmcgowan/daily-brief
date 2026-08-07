"""One-shot script: expand summaries and add rbtl for all top stories in corpus.json."""
import json, os

ROOT = os.path.dirname(os.path.abspath(__file__))
PATH = os.path.join(ROOT, "corpus.json")

UPDATES = {
    "claude-fable-5-launch": {
        "summary": "Anthropic officially launched Claude Fable 5 — the first model in their Fable series and their most capable public release to date. Positioned above Claude 3.7 Sonnet, it delivers major improvements in extended reasoning, agentic task handling, and coding performance. The model shipped with a companion lighter variant for cost-sensitive deployments and was immediately available in the API and Claude.ai across subscription tiers.",
        "rbtl": "The dual naming — Fable 5 externally, Mythos 5 internally — and the simultaneous lighter companion reveal a product tiering strategy that mirrors OpenAI's o-series/GPT-4o split. Anthropic is no longer just a safety lab releasing research artifacts; this launch reads like a product organization that has learned to compete on release cadence and market positioning.",
    },
    "openai-s1-tldr": {
        "summary": "OpenAI filed a confidential S-1 with the SEC to begin the formal IPO process, targeting a valuation in the hundreds of billions. The filing follows OpenAI's recent conversion from a nonprofit-capped-profit to a for-profit benefit corporation — a prerequisite for going public. The IPO would be among the largest tech listings in history, giving OpenAI permanent access to capital markets and a new class of accountability: public shareholders.",
        "rbtl": "The IPO filing caps a deliberate multi-year power shift at OpenAI — from nonprofit research lab to capital-markets-facing company. Once public, OpenAI's decisions will be governed by quarterly earnings pressure, not mission statements, and that changes everything: safety commitments, model pricing, partner exclusivity, and competitive behavior all become subject to investor return expectations.",
    },
    "anthropic-series-h": {
        "summary": "Anthropic closed a massive Series H funding round at a valuation approaching $1 trillion, making it one of the most highly valued private companies in history. The round was led by major institutional investors and technology conglomerates, giving Anthropic a multi-year runway for compute, research, and commercialization. Total capital raised now exceeds what most frontier AI labs have collectively accumulated.",
        "rbtl": "A near-$1T private valuation is less a fundraising event and more a negotiating signal: it sets a floor that effectively rules out acquisition and commits Anthropic to either an IPO or sustained market dominance. The number tells enterprise buyers and governments that Anthropic is a permanent counterparty — as serious as any tech giant — at precisely the moment procurement decisions are being locked in for years.",
    },
    "claude-opus-48": {
        "summary": "Anthropic released Claude Opus 4.8, upgrading their top-tier model with substantial gains in complex multi-step reasoning, long-horizon agentic workflows, and extended context handling. The release shipped alongside Claude Code updates that introduce dynamic, conditional workflow structures — letting agents branch, retry, and self-correct mid-task without manual intervention. Together they represent Anthropic's most complete push into agentic developer tooling.",
        "rbtl": "Releasing Opus 4.8 alongside Fable 5 in the same window creates a two-tier product lineup that mirrors how enterprises actually buy: one model for benchmarks and RFPs, another for cost-sensitive production. The Claude Code dynamic workflow additions are the more strategically important signal — Anthropic is betting that owning the agentic coding runtime is the highest-margin position in the near term.",
    },
    "gemini-35-translate": {
        "summary": "Google launched Gemini 3.5 with Live Translate as its flagship feature: real-time speech translation across languages with low latency and natural conversational cadence. The capability is embedded in Google Assistant, Pixel hardware, and Workspace, enabling live multilingual meetings without switching apps or using a third-party service. It represents Google's most consumer-visible AI feature in years.",
        "rbtl": "Live Translate plays to the one advantage no pure-play AI lab can replicate: device-level integration across 2B+ active users, hardware microphone access, and ambient OS embedding. This is Google retaliating against OpenAI's voice and realtime modes on its home turf — and Google's distribution moat is the one structural advantage OpenAI genuinely cannot buy its way into.",
    },
    "trump-openai-stake": {
        "summary": "Reports emerged that the Trump administration is pursuing a government equity stake in OpenAI, with the arrangement involving preferential national security access to OpenAI models in exchange for investment or favorable regulatory treatment. The deal would be the first known case of a U.S. government taking equity in a major AI lab and would coincide with OpenAI's IPO preparations.",
        "rbtl": "Government equity in an AI lab is without modern precedent and fundamentally changes OpenAI's independence calculus: once the state is a stakeholder, decisions about model capabilities, export controls, and safety commitments become subject to political interests in ways that safety-focused competitors like Anthropic and DeepMind can now credibly use as a differentiator with international and enterprise customers.",
    },
    "every-after-automation": {
        "summary": "Every editor Dan Shipper argues that advanced AI automation creates more meaningful human work rather than less, as the premium on distinctly human contributions — taste, judgment, relationships, framing the right question — rises when AI handles routine cognitive tasks. The essay draws on knowledge workers already operating with heavy AI assistance and finds that the most productive adapt by directing AI rather than competing with it. Shipper frames this as a structural shift in what expertise means.",
        "rbtl": "The argument is compelling but quietly concentrates its benefits: the workers whose output becomes more valuable are those who already had the leverage and skill to direct AI rather than compete with it. Workers displaced from the routine tasks being automated are not the same ones who get to move up to the judgment layer — and that distribution problem is the piece this narrative consistently sidesteps.",
    },
    "cursor-design-mode": {
        "summary": "Cursor released Design Mode, a visual interface layer inside the AI code editor that lets developers click UI elements, describe changes in natural language, and have those edits propagate directly into the codebase. The feature bridges the traditional gap between design tools and the IDE, enabling iterative visual refinement without leaving the code environment. It works across component libraries and can read the existing code structure to apply changes in context.",
        "rbtl": "Design Mode is a quiet existential threat to the Figma-to-code handoff workflow — it makes visual UI editing a developer-native activity rather than a designer-led one. If it matures, it doesn't just improve developer productivity; it shifts who 'owns' UI decisions in product teams toward engineers using AI tooling, which has implications for how design and engineering organizations structure themselves.",
    },
    "figma-make-local-code": {
        "summary": "Figma launched Make on Local Code, an integration that applies design changes from Figma directly to an existing local codebase, maintaining a live connection between design source-of-truth and shipped code. Alongside it, Figma shipped Check Designs (AI-powered design critique and consistency checking) and a remote MCP server that lets external AI agents query Figma data programmatically. The three features together constitute Figma's most significant AI infrastructure expansion.",
        "rbtl": "Figma's MCP ecosystem is a strategic bet that the future of design tooling is being a data provider to AI agents rather than a visual workspace for humans. By positioning Figma as the authoritative design layer that agents can read and write, they stay embedded in the AI-assisted product development workflow even as code generation tools threaten to commoditize the handoff step they've historically owned.",
    },
    "spacex-ai1-satellite": {
        "summary": "SpaceX revealed plans for an AI compute satellite constellation, provisioning distributed machine learning infrastructure from orbit outside traditional data center constraints. Google signed a major agreement to lease capacity from the constellation, and Anthropic is reportedly in discussions for similar arrangements. The architecture would allow model inference and training workloads to operate in geosynchronous or low-Earth orbit.",
        "rbtl": "Orbital AI compute is a geopolitical play as much as a technical one — infrastructure physically located outside any jurisdiction, harder to regulate, inspect, or shut down than ground-based data centers. Whoever controls orbital compute infrastructure in the next decade is positioning to set the terms for where AI governance actually applies, and current AI governance frameworks were not designed with this scenario in mind.",
    },
    "cheaper-ai-models": {
        "summary": "A wave of analysis has documented the dramatic pace of AI inference cost deflation: token prices for frontier-model-quality inference have fallen 10–100x in under two years, driven by hardware improvements, model distillation, and fierce competitive pressure from open-weight alternatives. Tasks requiring expensive GPT-4 API calls in 2023 can now be run cost-effectively using smaller or open models. The floor is still falling.",
        "rbtl": "Inference cost deflation is quietly the most important structural shift in AI deployment: it transforms AI from a capability story into a volume story. The business model question is no longer 'can we afford AI' but 'what defensible value sits above commoditized inference' — and most current AI SaaS startups are being built on margin compression they haven't fully priced in.",
    },
    "apple-core-ai": {
        "summary": "Apple unveiled the architecture of Apple Intelligence, centering on on-device inference, Private Cloud Compute (a privacy-preserving cloud extension that processes requests without Apple seeing the data), and deeply integrated system-level AI features across iOS, macOS, and hardware. The strategy prioritizes user privacy and seamless integration over raw model capability, with most features designed to work without an internet connection.",
        "rbtl": "Apple's privacy-first AI positioning is both genuine and strategically brilliant — it differentiates on the one dimension where OpenAI and Google structurally cannot compete without abandoning their core business models. With 2B+ active devices, Apple doesn't need to win the benchmark race; they need to win the trust race, and they are running it with an insurmountable distribution head start.",
    },
    "microsoft-seven-models": {
        "summary": "Microsoft announced a portfolio of seven proprietary MAI (Microsoft AI) models spanning different capability tiers — from small, edge-deployable reasoning models to large multimodal flagships — aimed at covering enterprise AI workloads without full dependency on OpenAI's model family. Several target specific verticals including code generation, document understanding, and vision tasks. The lineup is available through Azure AI and Copilot integrations.",
        "rbtl": "Seven models is a hedge, not a product strategy. Microsoft is building parallel model capability specifically so that if OpenAI's post-IPO pricing changes, exclusivity terms shift, or the partnership sours, Microsoft can silently route enterprise workloads to its own stack. This is the most strategically important AI supply-chain story most coverage is missing — Microsoft is quietly ending its dependency on OpenAI.",
    },
    "open-vs-closed-models": {
        "summary": "Interconnects author Nathan Lambert argues that the open vs. closed AI model debate has become less about capability gaps — which are narrowing — and more about deployment infrastructure, safety accountability, and commercial ecosystem dynamics. He contends that open-weight models are winning at the application layer while closed models retain advantages in reasoning benchmarks and enterprise trust. The distinction increasingly matters at the policy and procurement level.",
        "rbtl": "The open/closed framing has become a proxy for a deeper question: who is accountable when a deployed model causes harm? As open-weight models reach near-frontier capability, governments and enterprises will have to decide whether 'open' means 'unaccountable' — and that regulatory determination will reshape the market far more than any benchmark result.",
    },
    "a16z-visual-ai-code": {
        "summary": "Andreessen Horowitz published analysis examining how AI is collapsing the gap between visual design and code — with tools like Cursor Design Mode, Vercel v0, and Figma MCP enabling design-to-code and code-to-design workflows that previously required separate specialist handoffs. The piece argues this convergence represents a fundamental change in how digital products are built, with AI serving as the translation layer between intent and implementation.",
        "rbtl": "a16z framing this as a 'convergence' understates the power shift involved: these tools don't just make handoffs faster, they make the designer/developer boundary negotiable in real time. The firms that recognize this early and restructure product teams accordingly — rather than just adding AI tools to existing workflows — will build products faster than those still maintaining clean design/engineering separations.",
    },
    "latent-space-github": {
        "summary": "The Latent Space podcast published a deep-dive on GitHub's AI coding strategy, examining how Copilot has evolved from a tab-completion tool to an agentic coding assistant capable of multi-file edits, PR reviews, and autonomous task execution. The episode covers GitHub's positioning against Cursor, Windsurf, and Claude Code, and how the combination of GitHub's code index and Microsoft's model access creates structural advantages.",
        "rbtl": "GitHub's advantage is the one Cursor cannot replicate: a decade of indexed code history across billions of repositories, plus organizational trust that took years to earn. If GitHub executes on its agentic roadmap, Cursor's best exit is acquisition — and the episode implicitly makes the case that GitHub is competing to prevent exactly that outcome.",
    },
    "every-ai-ready-orgs": {
        "summary": "Every published analysis on what organizational structures and cultures produce the highest AI adoption ROI, based on patterns across companies making measurable AI-driven productivity gains. Three factors distinguish high-adoption organizations: centralized AI coordination paired with decentralized experimentation, a culture of written-first documentation that AI agents can act on, and executive teams who personally use AI tools rather than just sponsoring initiatives.",
        "rbtl": "The 'executives must use AI themselves' finding is the most practically important and the hardest to implement — organizations where AI is a sponsored strategic initiative but not a leadership habit will systematically lag those where leaders develop genuine intuitions about AI's limits, quirks, and highest-leverage applications. The gap between 'AI strategy' and 'AI habit' is where most enterprise AI initiatives fail quietly.",
    },
    "bads-agentic-design-system": {
        "summary": "BADS (Behavior-first Agentic Design System) introduces a framework for designing UI component libraries where AI agents are treated as first-class interactors alongside human users. Rather than designing purely for human click paths, BADS proposes that each component should expose behavioral APIs — declaring its capabilities, constraints, and interaction affordances — so agents can navigate and operate UIs programmatically. The framework addresses a real gap as AI agents increasingly operate production interfaces.",
        "rbtl": "BADS articulates the design system problem that will matter most in three years: components built for human interaction patterns break or behave unpredictably when AI agents navigate them. If agentic UI interaction becomes standard, the question of whether a design system is 'agent-readable' will be as important as whether it's accessible — and most design systems are not even close to ready.",
    },
    "slack-ai-design-validation": {
        "summary": "Slack shared how its design team uses AI to validate UI changes at scale before shipping — running automated checks for consistency, accessibility, and design system compliance across component variants. The workflow integrates AI review as a pre-merge step in the design pipeline, catching issues that would previously require manual design review or post-ship QA. The approach has reduced design review cycles while increasing consistency across Slack's component library.",
        "rbtl": "Slack's framing — AI as a design quality gate rather than a design generator — is a more durable use case than AI-generated UI: validation is less subjective, the failure modes are more detectable, and the ROI is easier to measure. This is the pattern most mature design systems will adopt first, before generative AI reaches the quality bar for production UI work.",
    },
    "speed-of-prototyping-ai": {
        "summary": "Analysis of how AI tools — from v0 and Bolt to Claude and Cursor — are compressing the prototyping timeline from days to hours, enabling product teams to explore 10x more design directions before committing to implementation. The piece documents specific workflows where AI generates functional prototypes from briefs or sketches, with humans iterating on the result rather than building from scratch. The shift changes what counts as 'done' at the prototype stage.",
        "rbtl": "Faster prototyping sounds like a pure win, but it creates a selection problem: when it's cheap to explore 20 directions, the bottleneck moves to knowing which direction to pursue — which requires sharper product judgment, not more prototypes. Teams without that judgment will prototype more and decide worse; teams with it will move faster than anything seen in traditional product development.",
    },
    "nngroup-ai-design-jobs": {
        "summary": "Nielsen Norman Group published research on how AI is restructuring UX and product design roles based on practitioner surveys across industries. The study documents a measurable shift: designers are spending less time on production deliverables and significantly more time on direction-setting, AI output curation, research synthesis, and quality review. Four new role patterns are emerging — AI Director, AI Validator, AI Collaborator, and AI Delegator — each representing a different relationship with AI tooling.",
        "rbtl": "NNG's four-role taxonomy is useful for understanding current transitions, but the more important finding is structural: if AI handles the production work that used to develop junior designers' craft, the next generation of senior designers will arrive with narrower foundational skills. The field is compressing the junior-to-senior pipeline at the same time it's raising expectations for what senior designers can do.",
    },
    "airbnb-ceo-ai-design": {
        "summary": "Airbnb CEO Brian Chesky publicly stated that AI is actively replacing product managers and beginning to reshape designer roles within Airbnb's product organization. He described the shift as enabling faster, more direct product iteration with smaller, more senior teams — and argued this pattern will accelerate across the industry. Chesky cited Airbnb's own internal use of AI design workflows as evidence that the transition is already underway.",
        "rbtl": "When a CEO says 'AI is replacing PMs,' what typically follows is that engineers with AI interfaces absorb product decision-making authority — which is less a story about AI and more about which function wins the internal power struggle. Chesky saying this publicly is also a negotiating signal to his own workforce about role expectations and team sizing, timed to coincide with Airbnb's next product cycle.",
    },
}

with open(PATH, "r", encoding="utf-8") as f:
    corpus = json.load(f)

updated = 0
for item in corpus["items"]:
    iid = item.get("id", "")
    if iid in UPDATES:
        item.update(UPDATES[iid])
        updated += 1

with open(PATH, "w", encoding="utf-8") as f:
    json.dump(corpus, f, ensure_ascii=False, indent=2)

print(f"[patch_corpus] Updated {updated} items with expanded summaries + rbtl.")
