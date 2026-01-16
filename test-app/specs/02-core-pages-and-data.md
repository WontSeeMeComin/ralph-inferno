# 02-core-pages-and-data

> Epic: Aussie Atlas
> Dependencies: 01-project-setup

---

## Goal
Implement the app shell + core pages with data-driven content about Australian Shepherds.

---

## Functional Requirements (FR)

### FR1: App shell
- Header with nav links
- Footer with small attribution/resources
- Responsive layout

**Acceptance Criteria:**
- [ ] Header nav works on mobile and desktop

### FR2: Breed overview on Home
Home page should include:
- Short intro paragraph
- “Quick facts” (size, energy, coat, trainability)
- CTA link to the quiz

**Acceptance Criteria:**
- [ ] Home page shows at least 4 quick facts

### FR3: Characteristics page
Include:
- Temperament notes
- Pros/cons style list

**Acceptance Criteria:**
- [ ] Characteristics page renders from typed data

### FR4: Care + Health pages
Care:
- Exercise needs
- Grooming checklist
- Training tips

Health:
- Common concerns (e.g., hip dysplasia, MDR1 sensitivity, eye issues)
- “When to talk to a vet” disclaimer

**Acceptance Criteria:**
- [ ] Care and Health content is structured (headings + lists)

---

## Technical Implementation

### Data model
Create a typed data module (e.g. `src/data/aussie.ts`) exporting:
- Quick facts
- Care tips (with categories)
- Health notes

### Component guidance
- Use reusable `Card`, `Badge`, `Section` components
- Keep pages thin: assemble sections from components

---

## Done when
- [ ] `npm run build` passes
- [ ] `npx playwright test` passes
