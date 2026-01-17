# /ralph:idea - Start Discovery Loop

Autonomous exploration of a product idea from all angles with web research.

## Usage
```
/ralph:idea "Your product idea here"
```

## Instructions

**YOU SHOULD RUN AN AUTONOMOUS DISCOVERY LOOP**

Explore the idea by switching between roles. Use WebSearch actively for research.
Iterate until the PRD is complete and all questions answered.

---

**PHASE 1: INITIAL RESEARCH (Analyst)**

```
🔍 ANALYST MODE
```

1. WebSearch: Search for similar products/services
2. WebSearch: Search for potential integrations (APIs)
3. identify competitors and their strengths/weaknesses
4. Document market size if possible

Write down findings in section: `## Market Research`

---

**PHASE 2: USERS & FLOWS (UX)**

```
👤 UX MODE
```

1. define 2-3 personas (who are the users?)
2. sketch main user flows
3. identify critical interaction points
4. think about the onboarding flow

Write down in sections: `## Target Users & Personas`, `## User Flows`

---

**PHASE 3: SCOPE & PRIORITIZATION (PM)**

```
📋 PM MODE
```

1. list all potential features
2. prioritize: what is MVP? What can wait?
3. define "done" for MVP
4. Identify risks and dependencies

Write down in section: `## Core Features (MVP)`, `## Future Features`

---

**PHASE 4: TECHNICAL DESIGN (Architect)

```
🏗️ ARCHITECT MODE
```

1. WebSearch: Search for relevant APIs and documentation
2. Select tech stack based on requirements
3. list all external integrations
4. Identify technical challenges

Write down in sections: `## Technical Requirements`, `## Integrations Required`

---

**Phase 5: BUSINESS & LEGAL (Business)**

```
💼 BUSINESS MODE
```

1. define business model (how do we make money?)
2. WebSearch: Search for legal requirements (GDPR, PCI-DSS etc)
3. identify compliance requirements
4. Estimate costs (APIs, hosting)

Write down in sections: `## Business Model`, `## Legal/Compliance`

---

**PHASE 6: SYNTHESIS & VALIDATION**

```
✅ VALIDATION MODE
```

1. read through all sections
2. are there open questions? → Add to `## Open Questions`
3. are there conflicts between sections? → Resolve them
4. Is the tech stack consistent with requirements? → Verify

**ITERATE** if Open Questions is not empty:
- Go back to relevant role
- Do more research
- Update sections

---

**EXIT CRITERIA**

The loop is complete when
- [ ] All sections have meaningful content
- [ ] `## Open Questions` is empty or contains only "nice-to-have"
- [ ] Tech stack is decided and documented
- [ ] All critical integrations are identified
- [ ] MVP scope is clearly defined

---

**OUTPUT**

Create `docs/PRD.md` with the following structure

```markdown
# [Product Name] - PRD

## Vision & Problem
{What are we solving? Why is this needed?}

## Market Research
{Competitors, market, opportunities}

## Target Users & Personas
{Who are the users? 2-3 personas}

## User Flows
{Main flows, step by step}

## Core Features (MVP)
{Prioritized list, what must exist}

## Future Features
{What can wait for v2?}

## Technical Requirements
{Stack, architecture, constraints}

## Integrations Required
{External APIs and services}

## Business Model
{How do we make money?}

## Legal/Compliance
{GDPR, PCI-DSS, other requirements}

## Open Questions
{MUST BE EMPTY to be complete}
```

---

**WHEN READY**

Type:
```
DISCOVERY_COMPLETE

PRD saved to: docs/PRD.md

Next steps:
1. Run /ralph:preflight to verify requirements
2. Run /ralph:plan to create implementation plan
```
