"""One-shot: add 2026-06-11 stories + update last_seen on recurring items."""
import json, os

ROOT = os.path.dirname(os.path.abspath(__file__))
PATH = os.path.join(ROOT, "corpus.json")

TODAY = "2026-06-11"

NEW_ITEMS = [
    # --- AI-agent payments cluster (TLDR Fintech) ---
    {
        "id": "visa-openai-agentic-payments",
        "title": "Visa and OpenAI form agentic commerce partnership",
        "url": "https://links.tldrnewsletter.com/2CMa40",
        "source": "TLDR Fintech (email)",
        "source_type": "email",
        "topic": "ai",
        "topics": ["ai", "tech"],
        "summary": "Visa announced a partnership with OpenAI to provide its global payment network, credentialing infrastructure, and security capabilities for agent-initiated transactions. The integration will be built directly into ChatGPT and the OpenAI API, enabling developers and merchants to accept Visa payments initiated by AI agents without building separate payment infrastructure. It marks the first time a major card network has formally embedded its rails into a frontier AI platform.",
        "rbtl": "Visa embedding its payment rails into ChatGPT's agent layer is the financial industry's opening move in the race to capture agentic commerce — whoever sets the standard for how agents pay becomes the invisible intermediary for every autonomous transaction, and that volume will eventually dwarf human-initiated digital commerce.",
        "first_seen": TODAY,
        "last_seen": TODAY,
        "cluster": "ai-agent-payments",
        "score": 8,
        "pinned": False,
    },
    {
        "id": "mastercard-agent-pay",
        "title": "Mastercard launches Agent Pay for Machines",
        "url": "https://links.tldrnewsletter.com/paryuY",
        "source": "TLDR Fintech (email)",
        "source_type": "email",
        "topic": "ai",
        "topics": ["ai", "tech"],
        "summary": "Mastercard launched 'Agent Pay for Machines,' an infrastructure layer designed for AI agents to initiate and complete financial transactions at machine speed, including high-velocity chains of microtransactions. The system envisions a future where businesses create services specifically for AI agents to purchase and use autonomously. Visa made a similar announcement on the same day, signaling a coordinated industry move toward agentic payment rails.",
        "rbtl": "Visa and Mastercard both announcing agentic payment infrastructure on the same day signals that the financial rails race for AI agents has begun in earnest — and the two incumbents clearly prefer to define the standard before a faster-moving fintech does it for them.",
        "first_seen": TODAY,
        "last_seen": TODAY,
        "cluster": "ai-agent-payments",
        "score": 8,
        "pinned": False,
    },
    # --- Dario Amodei AI policy ---
    {
        "id": "dario-amodei-policy-ai",
        "title": "Policy on the AI Exponential",
        "url": "https://darioamodei.com/post/policy-on-the-ai-exponential",
        "source": "TLDR AI (email)",
        "source_type": "email",
        "topic": "ai",
        "topics": ["ai"],
        "summary": "Anthropic CEO Dario Amodei published his most detailed public regulatory roadmap to date, proposing an FAA-style federal AI regulator with mandatory safety testing and stronger cybersecurity standards. He also addresses macroeconomic adaptations for AI-driven growth, tax policy reforms, and ensuring AI development aligns with democratic values globally. The post is one of the most comprehensive AI governance arguments from a sitting lab CEO.",
        "rbtl": "Amodei publishing a detailed regulatory blueprint publicly and under his own name is a calculated positioning move: it casts Anthropic as the lab that actively wants to be regulated, which differentiates it from competitors at precisely the moment enterprise procurement teams and government contracting officers are asking hard questions about vendor accountability.",
        "first_seen": TODAY,
        "last_seen": TODAY,
        "cluster": "ai-policy-2026",
        "score": 9,
        "pinned": False,
    },
    # --- Fable 5 system prompt leak (cluster: claude-fable-5) ---
    {
        "id": "fable5-system-prompt-leak",
        "title": "Fable 5 system prompt leaked in full",
        "url": "https://links.tldrnewsletter.com/iHUGuo",
        "source": "TLDR AI (email)",
        "source_type": "email",
        "topic": "ai",
        "topics": ["ai"],
        "summary": "Anthropic's Fable 5 system prompt was leaked in full, totaling approximately 120,000 characters. The document reveals detailed instructions governing how Fable 5 handles safety, reasoning, refusals, and agentic behavior at the highest tier of model capability — a rare window into how frontier models are actually constrained at deployment.",
        "rbtl": "A 120,000-character system prompt leak maps the entire operational constraint surface for Fable 5 — for competitors and researchers it's a roadmap, and for users it clarifies the gap between Anthropic's stated safety behavior and what's actually reproducible in production deployments.",
        "first_seen": TODAY,
        "last_seen": TODAY,
        "cluster": "claude-fable-5",
        "score": 7,
        "pinned": False,
    },
    # --- Every: Fable 5 team review (cluster: claude-fable-5) ---
    {
        "id": "every-ai-everywhere-fable5",
        "title": "AI Everywhere, All at Once — Every's Fable 5 verdict",
        "url": "https://every.to/context-window/ai-everywhere-all-at-once",
        "source": "Every (email)",
        "source_type": "email",
        "topic": "ai",
        "topics": ["ai"],
        "summary": "Every's Context Window covered how the team adapted their workflows to Fable 5 after a week of testing, settling on a two-prong approach: Fable 5 for large, complex, delegatable tasks; smaller coding agents for iterative work. The issue includes a Fable 5 prompt starter library for eight common knowledge-work workflows and an Apple WWDC field report on Siri's improvements.",
        "rbtl": "",
        "first_seen": TODAY,
        "last_seen": TODAY,
        "cluster": "claude-fable-5",
        "score": 7,
        "pinned": False,
    },
    # --- Moats Need Models ---
    {
        "id": "moats-need-models",
        "title": "Moats Need Models",
        "url": "https://links.tldrnewsletter.com/LktVYs",
        "source": "TLDR AI (email)",
        "source_type": "email",
        "topic": "ai",
        "topics": ["ai"],
        "summary": "A widely-circulated essay argues that defensibility in AI products comes from owning the full feedback loop — model, harness, workflow, and evaluation — rather than renting frontier capability from third parties. The piece contends that model, tooling, and evaluation are no longer separable stack pieces but co-design surfaces that compound together over time.",
        "rbtl": "The 'moat comes from the loop' argument is the business-case version of what Anthropic and OpenAI have been building toward architecturally: if you rent their frontier model, they own your feedback loop. Companies that understand this will treat evaluation infrastructure as a strategic asset, not an afterthought — and those that don't are building on rented ground.",
        "first_seen": TODAY,
        "last_seen": TODAY,
        "cluster": None,
        "score": 7,
        "pinned": False,
    },
    # --- Claude Managed Agents ---
    {
        "id": "claude-managed-agents",
        "title": "Building with Claude Managed Agents",
        "url": "https://claude.com/blog/building-with-claude-managed-agents",
        "source": "TLDR AI (email)",
        "source_type": "email",
        "topic": "ai",
        "topics": ["ai"],
        "summary": "Anthropic published a guide to Claude Managed Agents — composable APIs with integrated infrastructure for production-grade agentic systems. The post covers how managed agents simplify orchestration, handle tool use and memory persistence, and enable reliable long-horizon workflows without custom infrastructure management.",
        "rbtl": "Anthropic launching 'managed agents' as a product concept — not just an API — is a bid to become the ops layer for enterprise AI, not just the model provider. Developers building production agents on Anthropic's managed infrastructure accumulate switching costs that don't exist when renting the raw model.",
        "first_seen": TODAY,
        "last_seen": TODAY,
        "cluster": None,
        "score": 7,
        "pinned": False,
    },
    # --- Palantir Karp unhappy ---
    {
        "id": "palantir-karp-ai-labs",
        "title": "Palantir's Karp says businesses are 'unhappy' with frontier AI labs",
        "url": "https://www.cnbc.com/2026/06/10/palantir-karp-enterprise-ai.html",
        "source": "TLDR AI (email)",
        "source_type": "email",
        "topic": "ai",
        "topics": ["ai"],
        "summary": "Palantir CEO Alex Karp stated publicly that the company's enterprise customers are 'unhappy' with how frontier AI labs operate, claiming the labs focus on burning through tokens as a proxy for productivity rather than generating real enterprise ROI. He argues accelerating AI costs are raising alarms among businesses and fueling efficiency concerns about whether frontier models are actually delivering value.",
        "rbtl": "Karp is selling the operational layer on top of frontier models, so this comment is promotional — but he's naming a real divergence: frontier labs compete on model capability and researchers, while enterprises care about reliability, cost predictability, and auditability. That gap is real and growing.",
        "first_seen": TODAY,
        "last_seen": TODAY,
        "cluster": None,
        "score": 7,
        "pinned": False,
    },
    # --- EU / Meta WhatsApp ---
    {
        "id": "eu-meta-whatsapp-chatbots",
        "title": "EU orders Meta to stop blocking rival AI chatbots on WhatsApp",
        "url": "https://www.engadget.com/2191213/eu-orders-meta-to-stop-blocking-rival-ai-chatbots-on-whatsapp/",
        "source": "TLDR AI (email)",
        "source_type": "email",
        "topic": "tech",
        "topics": ["tech"],
        "summary": "",
        "rbtl": "",
        "first_seen": TODAY,
        "last_seen": TODAY,
        "cluster": None,
        "score": 6,
        "pinned": False,
    },
    # --- DiffusionGemma ---
    {
        "id": "diffusion-gemma-faster",
        "title": "DiffusionGemma: 4x Faster Text Generation",
        "url": "https://blog.google/innovation-and-ai/technology/developers-tools/diffusion-gemma-faster-text-generation/",
        "source": "TLDR AI (email)",
        "source_type": "email",
        "topic": "ai",
        "topics": ["ai"],
        "summary": "",
        "rbtl": "",
        "first_seen": TODAY,
        "last_seen": TODAY,
        "cluster": None,
        "score": 6,
        "pinned": False,
    },
    # --- Cursor Bugbot ---
    {
        "id": "cursor-bugbot-update",
        "title": "Faster Code Review with Cursor's Bugbot",
        "url": "https://cursor.com/blog/bugbot-updates-june-2026",
        "source": "TLDR AI (email)",
        "source_type": "email",
        "topic": "ai_in_design",
        "topics": ["ai_in_design"],
        "summary": "",
        "rbtl": "",
        "first_seen": TODAY,
        "last_seen": TODAY,
        "cluster": None,
        "score": 6,
        "pinned": False,
    },
]

# IDs whose last_seen should be bumped (re-appeared today)
BUMP_IDS = {
    "openai-s1-tldr",   # OpenAI IPO appeared in TLDR Fintech today
}

with open(PATH, "r", encoding="utf-8") as f:
    corpus = json.load(f)

existing_ids = {it["id"] for it in corpus["items"]}
added, bumped = 0, 0

for item in corpus["items"]:
    if item["id"] in BUMP_IDS:
        item["last_seen"] = TODAY
        bumped += 1

for item in NEW_ITEMS:
    if item["id"] not in existing_ids:
        corpus["items"].append(item)
        added += 1

with open(PATH, "w", encoding="utf-8") as f:
    json.dump(corpus, f, ensure_ascii=False, indent=2)

print(f"[patch_corpus_june11] Added {added} new items, bumped last_seen on {bumped} existing items.")
