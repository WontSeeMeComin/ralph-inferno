# PROMPT_build.md - Implementation

> One task per iteration. Commit when tests pass." - Geoffrey Huntley

**Read first:** CLAUDE.md for context zones, subagent rules, and code philosophy.

---

## Phase 0: Orientation

1. read IMPLEMENTATION_PLAN.md → identify next task
2. Search existing code with subagents (up to 500 parallel)
3. Have src/* as reference for patterns

---

## Phase 1: Select ONE Task

```
1. Read IMPLEMENTATION_PLAN.md
2. Select highest priority incomplete task
3. If HARD STOP → pause, verify first
```

---

## Phase 2: Search First

**ALWAYS search before you create!

```bash
grep -r "function_name" src/
grep -r "ComponentName" src/components/
```

- NEVER assume something is missing
- Reuse existing code

---

## Phase 3: TDD

```
1. Write failing test
2. Implement minimal code
3. Run test (only 1 subagent)
4. If fail → fix (max 3 attempts)
5. Repeat until green
```

---

## Phase 4: Export & Integration Checklist

**CRITICAL - Do this after EACH new component/hook:**

```
1. New component created? → Add export to index.ts
   - src/components/{category}/index.ts
   - src/hooks/index.ts
   - src/contexts/index.ts

2. New hook/context created? → Update pages that will use it
   - Import in the right page
   - Connect props correctly

3. ALWAYS run after new file:
   npm run build

   If build fails → fix BEFORE commit
```

---

## Phase 5: HARD STOP Verification

**In case of HARD STOP between epics - do ALL these steps:**

```bash
# 1. Build verification
npm run build
# If errors → fix all errors

# 2. Start dev-server and test manually
npm run dev &
sleep 5
curl -s http://localhost:5173 | head -20
# Verify the page loads

# 3. Check that all routes work
# - / (redirect)
# - /login
# - /register
# - /todos (if auth complete)

# 4. If Supabase is used - verify connection
# Create test user if possible
```

**HARD STOP is NOT authorized until:**
- [ ] `npm run build` succeeds without error
- [ ] App starts and displays the correct page
- [ ] Basic navigation works

---

## Phase 6: Commit & Log in

```bash
# 1. Mark task complete in IMPLEMENTATION_PLAN.md
# 2. Log in Progress section
# 3. Commit
git add -A && git commit -m "feat: {description}"
```

---

## Supabase Setup (About in PRD)

**If the project uses Supabase - do this in E1:**

```bash
# 1. Initialize Supabase
cd {project}
supabase init

# 2. Create migration from schema
mkdir -p supabase/migrations
cp supabase/schema.sql supabase/migrations/$(date +%Y%m%d%H%M%S)_init.sql

# 3. Start local Supabase (requires Docker)
supabase start

# 4. Get credentials and update .env
supabase status
# Copy API URL and anon key to .env:
# VITE_SUPABASE_URL=http://127.0.0.1:54321
# VITE_SUPABASE_ANON_KEY=<from status>

# 5. Run migrations
supabase db reset

# 6. Verify
curl http://127.0.0.1:54321/rest/v1/ -H "apikey: <anon_key>"
```

**IMPORTANT:** Supabase must be running and .env configured BEFORE auth-tasks start.

---

## Parallel Build Integration

**After parallel run with worktrees:**

```
1. Each worktree builds isolated components
2. On merge → verify that ALL exports exist
3. Update pages to use new components
4. Run full build verification

Common problems after merge:
- Missing exports in index.ts
- Props not passed correctly
- Hooks not imported in pages
```

---

## Guardrails

```
99999. ONE task per iteration
99998. Search before you create
99997. Only 1 subagent for build/test
99996. Commit after each task
99995. HARD STOP = FULL verification (build + manual test)
99994. Stuck after 3 attempts → document in IMPLEMENTATION_PLAN.md
99993. New component = update index.ts IMMEDIATELY
99992. Supabase project = start local instance in E1
```

---

## Completion

When ALL tasks are completed:

```bash
# Final verification
npm run build && npm run dev &
sleep 5

# Test all flows
# If everything works:
echo "BUILD_DONE"
```
