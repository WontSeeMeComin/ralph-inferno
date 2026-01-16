# 03-quiz-and-favorites

> Epic: Aussie Atlas
> Dependencies: 02-core-pages-and-data

---

## Goal
Add an interactive “Is an Aussie right for me?” quiz and a favorites system for care tips.

---

## Functional Requirements (FR)

### FR1: Quiz flow
- Multi-question quiz (56 questions)
- Each question has 34 answer choices
- Compute a score and show a results screen

**Acceptance Criteria:**
- [ ] User can complete the quiz end-to-end
- [ ] Result page shows a clear recommendation

### FR2: Favorites
- Care tips can be favorited/unfavorited
- Favorites persist in localStorage
- Provide a “Favorites” view or section

**Acceptance Criteria:**
- [ ] Favoriting persists after refresh

---

## Technical Implementation

### Suggested structure
- `src/features/quiz/*`
- `src/features/favorites/*`
- `src/hooks/useLocalStorage.ts`

### State
- Keep quiz state in component state
- Favorites state can live in a small context or a hook

---

## Done when
- [ ] `npm run build` passes
- [ ] `npx playwright test` passes
