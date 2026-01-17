# 01-project-setup

> Epic: Foundation
> Dependencies: None (first spec)

---

## Target

Set up the basic structure of the project with all the necessary tools to allow Ralph to build and test autonomously.

---

## Functional Requirements (FR)

### FR1: Vite + React + TypeScript
Create new project with modern stack.

**Acceptance Criteria:**
- [ ] `npm run dev` starts dev server
- [ ] `npm run build` builds without errors
- [ ] TypeScript strict mode enabled

### FR2: Tailwind CSS
Configure Tailwind with design tokens from PRD.

**Acceptance Criteria:**
- [ ] Tailwind classes work
- [ ] Design tokens from PRD in `tailwind.config.js`
- [ ] CSS variables for theme

### FR3: Playwright E2E Testing
> ⚠️ CRITICAL for ralph's test loop

**Acceptance Criteria:**
- [ ] `npx playwright install` running
- [ ] `playwright.config.ts` configured
- [ ] `e2e/` folder created
- [ ] Smoke test exists and passes

### FR4: Vitest Unit Testing (if relevant)

**Acceptance Criteria:**
- [ ] `npm test` works
- [ ] Sample test passes

---

## Technical Implementation

### Commands to run
```bash
# 1. Create project
npm create vite@latest . -- --template react-ts

# 2. Install dependencies
npm install

# 3. Tailwind
npm install -D tailwindcss postcss autoprefixer
npx tailwindcss init -p

# 4. Playwright (CRITICAL!)
npm install -D @playwright/test
npx playwright install

# 5. Create playwright.config.ts
# 6. Create e2e/smoke.spec.ts
```

### Files to create

**playwright.config.ts:**
```typescript
import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: 'list',
  use: {
    baseURL: 'http://localhost:5173',
    trace: 'on-first-retry',
  },
  webServer: {
    command: 'npm run dev',
    url: 'http://localhost:5173',
    reuseExistingServer: !process.env.CI,
  },
});
```

**e2e/smoke.spec.ts:**
```typescript
import { test, expect } from '@playwright/test';

test('app loads successfully', async ({ page }) => {
  await page.goto('/');
  await expect(page).toHaveTitle(/./);  // Any title
  // Add more specific checks based on your app
});
```

**tailwind.config.js** (with design tokens):
```javascript
/** @type {import('tailwindcss').Config} */
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: {
    extend: {
      colors: {
        // Add from PRD Design System
        primary: 'var(--color-primary)',
        accent: 'var(--color-accent)',
        // ...
      },
      // Spacing, fonts etc from PRD
    },
  },
  plugins: [],
};
```

---

## E2E Test

**Test file:** `e2e/smoke.spec.ts`

**Tests to write:**
```typescript
test('app loads and shows content', async ({ page }) => {
  await page.goto('/');
  await expect(page.locator('body')).toBeVisible();
});
```

---

## Ready when

- [ ] `npm run dev` works
- [ ] `npm run build` passes
- [ ] `npx playwright test` passes
- [ ] Tailwind works (test with a class)
- [ ] Design tokens from PRD in config
- [ ] Project structure according to CLAUDE.md
