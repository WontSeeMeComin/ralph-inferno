# /ralph:plan - Create Implementation Plan

Analyze PRD and create implementation plan with executable specs.

## Usage
```
/ralph:plan
```

## Prerequisites
- `docs/prd.md` must exist (run `/ralph:discover` first)

## Output
- `docs/IMPLEMENTATION_PLAN.md` - Overview with epics and tasks
- `specs/*.md` - Executable spec files for each task (this runs ralph on VM)

## Instructions

Read `docs/prd.md` and create an implementation plan.

**PHASE 1: ANALYZE THE PRD**
1. read `docs/prd.md` carefully
2. identify all features and requirements
3. group into logical epics

**PHASE 2: CREATE IMPLEMENTATION_PLAN.md**

Create the file with this structure:

```markdown
# IMPLEMENTATION_PLAN.md

## Epics Overview

| Epic | Name | Status |
|------|------|--------|
| E1 | {name} | pending |
| E2 | {name} | pending |

## Tasks

### Critical (E1: {epic-name})
- [ ] T1: {Specific task}
- [ ] T2: {Task}
- [ ] **HARD STOP** - Verify base flow works

### High (E2: {epic-name})
- [ ] T3: {Task}
- [ ] T4: {Task}

### Low
- [ ] T5: {Task}

---

## Progress

| Date | Task | Result |
|------|------|--------|

---

## Learnings

| Problem | Lesson |
|---------|--------|

---

## Blocked
```

**PHASE 3: CREATE SPECS FILES (MANDATORY)**

ALWAYS create executable spec files in `specs/`. This is what ralph runs on the VM.

```
specs/
├── 01-project-setup.md
├── 02-{feature}.md
├── 03-{feature}.md
└── ...
```

**Spec file format (MINIMUM for small context window):**
```markdown
# {Task-name}

{1-2 sentences about what to build}

## Requirements
- {Concrete requirement 1}
- {Concrete requirement 2}

## Done when
- [ ] `npm run build` passes
- [ ] {Specific verification from PRD}
```

> Only include testing setup if the PRD explicitly requests it.

**IMPORTANT - KEEP SPECS MINIMAL:**
- MAX 20 lines per spec
- No background/context - Claude reads the code
- No implementation details - Claude knows how
- Only WHAT, not HOW
- One spec = one focused task

**EXAMPLE OF GOOD SPECS:**
```markdown
# Auth Context

Create React context for authentication with Supabase.

## Requirements
- AuthProvider wrapper
- useAuth hook (user, signIn, signOut)
- Automatic session refresh

## Done when
- [ ] `npm run build` passes
- [ ] Can log in/out via hook
```

**EXAMPLE OF BAD SPECS (too long):**
```markdown
# Auth Context

## Background
Authentication is important for...
[10 lines of context]

## Implementation
1. Create src/contexts/AuthContext.tsx
2. Import createContext from react
3. ...
[20 lines of implementation details]
```

**RULES:**
- One task = one sentence without "and"
- HARD STOP between priority levels
- Critical blockers first
- Tasks grouped under their epic

**WHEN READY:**
Type:
```
PLANNING_DONE

Next: Run /ralph:deploy to send to VM and start the build
```
