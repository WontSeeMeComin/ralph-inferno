# 04-filtering-and-e2e

> Epic: Aussie Atlas
> Dependencies: 03-quiz-and-favorites

---

## Goal
Add care-tip filtering/search and write comprehensive Playwright E2E tests for key user flows.

---

## Functional Requirements (FR)

### FR1: Filtering/search
- Filter care tips by category
- Optional text search over tip title/body

**Acceptance Criteria:**
- [ ] Filtering visibly changes the list
- [ ] Empty state is friendly (no results)

### FR2: E2E tests (meaningful)
Write Playwright tests that cover:

1) Navigation:
- Home  Characteristics  Care  Health  Quiz

2) Quiz:
- Answer all questions
- Verify results page shows recommendation text

3) Favorites persistence:
- Favorite a tip
- Reload page
- Verify the tip is still favorited / appears in Favorites view

4) Filtering:
- Filter to a category and assert only matching tips are shown

**Acceptance Criteria:**
- [ ] Tests assert meaningful UI state (not just “page loads”)
- [ ] `npx playwright test` passes reliably

---

## Technical Implementation

### Playwright guidance
- Start dev server for tests via Playwright webServer config
- Use stable selectors (role/text/data-testid)

---

## Done when
- [ ] `npm run build` passes
- [ ] `npx playwright test` passes
