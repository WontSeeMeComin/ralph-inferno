# /ralph:plan - Create Implementation Plan

Analyze PRD and create implementation plan with detailed, executable specs.

## Usage
```
/ralph:plan
```

## Prerequisites
- `docs/prd.md` must exist (run `/ralph:discover` first)

## Output
- `docs/IMPLEMENTATION_PLAN.md` - Overview with epics and tasks
- `specs/*.md` - Detailed executable spec files for each task

## Instructions

Read `docs/prd.md` and create an implementation plan.

**PHASE 1: ANALYZE THE PRD**
1. Read `docs/prd.md` carefully
2. Identify all features and requirements
3. Group into logical epics

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

**PHASE 3: CREATE DETAILED SPEC FILES (MANDATORY)**

ALWAYS create executable spec files in `specs/`. These specs will be executed by mid-tier OSS models, so they need EXPLICIT, DETAILED instructions.

```
specs/
├── 01-project-setup.md
├── 02-{feature}.md
├── 03-{feature}.md
└── ...
```

## SPEC FILE FORMAT (DETAILED FOR OSS MODEL EXECUTION)

The executor model may be a smaller OSS model (not Claude). It needs explicit step-by-step guidance:

```markdown
# {Task Name}

{1-2 sentences describing what to build}

## Implementation Steps

1. {Explicit step with exact command or action}
2. {Next step}
3. {Continue with specific instructions}

## Files to Create/Modify

### `path/to/file.ts`
{Description of what this file should contain}
```typescript
// Key code structure or example
interface Example {
  id: string;
}
```

### `path/to/another.ts`
{Description}

## Commands to Run
```bash
{Any npm/shell commands needed}
```

## Done when
- [ ] `npm run build` passes
- [ ] {Specific verification criteria}
```

## EXAMPLE OF GOOD DETAILED SPEC

```markdown
# Project Setup

Initialize Vite + React + TypeScript + Tailwind CSS project with folder structure.

## Implementation Steps

1. Initialize Vite project (if no package.json exists):
   ```bash
   npm create vite@latest . -- --template react-ts
   npm install
   ```

2. Install Tailwind CSS:
   ```bash
   npm install -D tailwindcss postcss autoprefixer
   npx tailwindcss init -p
   ```

3. Configure Tailwind in `tailwind.config.js`
4. Add Tailwind directives to `src/index.css`
5. Create folder structure under `src/`
6. Update `src/App.tsx` with minimal starting point

## Files to Create/Modify

### `tailwind.config.js`
Update content array to include all source files:
```javascript
export default {
  content: ['./index.html', './src/**/*.{js,ts,jsx,tsx}'],
  theme: { extend: {} },
  plugins: [],
}
```

### `src/index.css`
Replace contents with Tailwind directives:
```css
@tailwind base;
@tailwind components;
@tailwind utilities;
```

### `src/App.tsx`
Create minimal starting point:
```tsx
function App() {
  return (
    <div className="min-h-screen bg-gray-100">
      <h1 className="text-2xl font-bold p-4">App</h1>
    </div>
  )
}
export default App
```

### Folder Structure
Create these directories (with .gitkeep if empty):
- `src/components/`
- `src/pages/`
- `src/hooks/`
- `src/utils/`
- `src/data/`

## Commands to Run
```bash
npm install
npm run build
```

## Done when
- [ ] `npm run build` passes without errors
- [ ] `npm run dev` starts and shows the app
- [ ] Tailwind classes render correctly (visible styled h1)
```

## SPEC WRITING RULES

1. **Be explicit** - Don't assume the model knows common patterns
2. **Include code snippets** - Show expected file contents
3. **List exact commands** - Shell commands the model should run
4. **One task per spec** - Keep specs focused
5. **Clear done criteria** - Specific, verifiable conditions
6. **No testing unless PRD requests it** - Skip test setup by default
7. **Show pattern once, describe variations** - Don't repeat similar code

## BALANCING DETAIL VS FLEXIBILITY

The goal is to give the model enough to succeed WITHOUT over-constraining it.

**GOOD: Pattern + Variations**
```markdown
### `src/pages/HomePage.tsx`
Create the home page component:
```tsx
export function HomePage() {
  return (
    <div className="home-page">
      <h2 className="text-2xl font-bold text-brand-primary mb-4">Welcome</h2>
      <p className="text-gray-700">Welcome message here.</p>
    </div>
  );
}
```

### Additional Pages (follow HomePage pattern)
Create these pages with the same structure:
- `AboutPage.tsx` - title: "About Us"
- `ContactPage.tsx` - title: "Contact"
- `SettingsPage.tsx` - title: "Settings"
```

**BAD: Verbatim repetition**
```markdown
### `src/pages/HomePage.tsx`
[50 lines of code]

### `src/pages/AboutPage.tsx`
[50 nearly identical lines]

### `src/pages/ContactPage.tsx`
[50 nearly identical lines]
```

**The principle**: Show complexity ONCE with full code, then describe variations concisely. This gives the model:
- A concrete pattern to follow
- Specific data for each variation
- Freedom to adapt if something doesn't work

## WHY DETAILED SPECS MATTER

The executor may be a mid-tier model (ministral, qwen, etc.) running via LM Studio or Ollama. These models:
- Need explicit step-by-step instructions
- Benefit from code examples showing expected structure
- May not infer common patterns automatically
- Work better with concrete commands vs abstract descriptions

The frontier agent (you, during /ralph:plan) does the THINKING.
The executor agent follows INSTRUCTIONS.

**WHEN READY:**
Type:
```
PLANNING_DONE

Next: Run /ralph:deploy to send to VM and start the build
```
