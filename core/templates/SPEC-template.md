# {SPEC_NUMBER}-{spec-name}

> Epic: {EPIC_NAME}
> Dependencies: {list previous specs that must be ready}

---

## Target

{Brief description of what this spec is intended to achieve}

---

## Functional Requirements (FR)

### FR1: {Requirement 1}
{Detailed description}

**Acceptance Criteria:**
- [ ] {Testable Criterion 1}
- [ ] {Testable Criterion 2}

### FR2: {Requirement 2}
{Detailed Description}

**Acceptance Criteria:**
- [ ] {Testable Criteria}

---

## Technical Implementation

### Files to create/modify
- `src/path/to/file.ts` - {what}
- `src/path/to/other.ts` - {what}

### Data model (if relevant)
```typescript
interface Example {
  id: string;
  // ...
}
```

### API/Endpoints (if applicable)
- `GET /api/resource` - {description}
- `POST /api/resource` - {description}

---

## E2E Test

> ⚠️ CRITICAL: Write Playwright tests that verify functionality

**Test file:** `e2e/{spec-name}.spec.ts`

**Tests to write:**
```typescript
test('{description of test 1}', async ({ page }) => {
  // 1. {Step 1}
  // 2. {Step 2}
  // 3. Verify {result}
});

test('{description of test 2}', async ({ page }) => {
  // ...
});
```

**What the test should verify:**
- [ ] {User flow works}
- [ ] {Edge case is handled}
- [ ] {Error state is displayed correctly}

---

## Design Requirements

> Follow Design System from PRD.md

- [ ] Use correct color tokens
- [ ] Follow spacing-scale
- [ ] Responsive (mobile-first)
- [ ] Accessible (keyboard, screen reader)

---

## Ready when

- [ ] All FR implemented
- [ ] E2E tests written and passing
- [ ] `npm run build` passes
- [ ] No TypeScript errors
- [ ] Follows design system
