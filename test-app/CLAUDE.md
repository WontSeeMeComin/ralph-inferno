# CLAUDE.md - Aussie Atlas (Australian Shepherd React App)

## Goal
Build a small, polished React app about **Australian Shepherds** (Aussies) that demonstrates:

- Good information architecture (pages/sections)
- Clean UI with Tailwind
- A small interactive feature (quiz + favorites)
- Strong Playwright E2E coverage (real user flows)

## Stack
- React + TypeScript
- Vite
- Tailwind CSS
- React Router
- Playwright E2E

## Coding rules
- Named exports
- Keep components small and focused
- Prefer data-driven UI (breed facts/tips in a data module)
- Accessibility: semantic headings, labels, keyboard-friendly controls

## Verification
After each spec:
- `npm run build`
- `npx playwright test`
