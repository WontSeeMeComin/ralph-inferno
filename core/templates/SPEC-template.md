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

## Design Requirements

> Follow Design System from PRD.md (if applicable)

- [ ] Use correct color tokens
- [ ] Follow spacing scale
- [ ] Responsive (mobile-first)
- [ ] Accessible (keyboard, screen reader)

---

## Ready when

- [ ] All FR implemented
- [ ] Build passes (if applicable)
- [ ] Tests pass (if configured in PRD)
- [ ] Follows design system (if applicable)
