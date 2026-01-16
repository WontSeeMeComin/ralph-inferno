# 01-project-setup

> Epic: Aussie Atlas
> Dependencies: none

---

## Goal
Scaffold the React app with routing, styling, and testing foundations.

---

## Functional Requirements (FR)

### FR1: App scaffold
Create a Vite + React + TypeScript project in `test-app/`.

**Acceptance Criteria:**
- [ ] `npm run dev` starts successfully
- [ ] `npm run build` succeeds

### FR2: Tailwind CSS
Add Tailwind and base styles.

**Acceptance Criteria:**
- [ ] App uses Tailwind for layout/typography

### FR3: Routing
Add React Router with at least: Home, Characteristics, Care, Health, Quiz.

**Acceptance Criteria:**
- [ ] Navigation works between all routes

### FR4: Playwright
Add Playwright with a basic config and an initial smoke test.

**Acceptance Criteria:**
- [ ] `npx playwright test` runs
- [ ] A smoke test visits home and sees the app title

---

## Technical Implementation

### Files to create/modify
- `package.json` - scripts for dev/build/test
- `vite.config.ts`
- `tailwind.config.*` + `postcss.config.*`
- `src/main.tsx`, `src/App.tsx`
- `src/routes/*`
- `playwright.config.ts`
- `e2e/smoke.spec.ts`

---

## Done when
- [ ] `npm run build` passes
- [ ] `npx playwright test` passes
