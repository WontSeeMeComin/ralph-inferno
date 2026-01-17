# /ralph:change-request - Create Change Request from Testing

Document bugs and issues found during testing, generate new specs for Ralph to fix.

## Usage
```
/ralph:change-request
```

## Prerequisites
- App has been built by Ralph (`/ralph:deploy` completed)
- Testing has been done (`/ralph:review` completed)
- Issues/bugs have been identified

## Output
- `docs/CHANGE_REQUEST.md` - Documentation of problem
- `specs/CR-*.md` - New specs files for fixes

## Instructions

**PHASE 1: COLLECT ISSUES**

Ask the user:
```
🔍 Change Request

Describe the problems you found during testing:
1. What didn't work as expected?
2. Which features are missing or incomplete?
3. Any UI/UX issues?

Paste your observations:
```

Wait for the user's input.

**PHASE 2: CATEGORIZE PROBLEMS**

Analyze input and categorize:

1. **BUGS** - Things that are broken/wrong
2. **INCOMPLETE** - Started but not finished
3. **MISSING** - Missing completely even though it was in specs
4. **ENHANCEMENT** - Improvements beyond original specs

**PHASE 3: CREATE CHANGE_REQUEST.md

Create `docs/CHANGE_REQUEST.md`:

```markdown
# Change Request - [DATE]

## Summary
{1-2 sentences about what was found}

## Categories

### 🐛 Bugs
| # | Problem | Affects | Priority |
|---|---------|---------|----------|
| B1 | {description} | {feature} | HIGH/MED/LOW |

### ⚠️ Incomplete
| # | Feature | Status | Missing |
|---|---------|--------|---------|
| I1 | {feature} | {%} | {what} |

### ❌ Missing
| # | Feature | Spec Reference |
|---|---------|----------------|
| M1 | {feature} | {original-spec} |

### 💡 Enhancements (Optional)
| # | Suggestion | Value |
|---|------------|-------|
| E1 | {suggestion} | {value} |

---

## Original Specs
{List which specs were run}

## Testing Done
{Summary of testing}
```

**PHASE 4: GENERATE NEW SPECS**

Create new specs files for each problem:

```
specs/
├── CR-01-fix-{bug}.md
├── CR-02-complete-{feature}.md
└── CR-03-add-{missing}.md
```

**Spec format for fixes:**
```markdown
# CR-XX: {Brief description}

{Problem}: {What is wrong}
{Fix}: {What needs to be done}

## Requirements
- {Concrete requirement 1}
- {Concrete requirement 2}

## Done when
- [ ] `npm run build` passes
- [ ] {Specific verification of fix}
- [ ] Regression: {existing functionality works}
```

**IMPORTANT:**
- Keep specs MINIMAL (max 15 lines)
- One spec = one problem
- Include regression test in "Done when"
- CR specs run AFTER original specs

**PHASE 5: UPDATE IMPLEMENTATION_PLAN.md**

Add CR tasks to `docs/IMPLEMENTATION_PLAN.md`:

```markdown
## Change Request Tasks

### CR-Fixes (Priority: Critical)
- [ ] CR-01: {fix}
- [ ] CR-02: {fix}
- [ ] **HARD STOP** - Verify all CR-fixes

### CR-Enhancements (Priority: Low)
- [ ] CR-03: {enhancement}
```

**WHEN READY:**
```
CHANGE_REQUEST_DONE

Created:
- docs/CHANGE_REQUEST.md
- X new specs in specs/CR-*.md

Next: Run /ralph:deploy to send CR-specs to VM
```
