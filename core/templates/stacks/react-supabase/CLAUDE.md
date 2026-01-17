# CLAUDE.md - React + Supabase Stack

## Stack
- Frontend: React 18+ with Vite
- Styling: Tailwind CSS
- Backend: Supabase (PostgreSQL, Auth, Realtime)
- Language: TypeScript

## Project structure

```
src/
├── components/
│   ├── ui/           # General UI components
│   ├── auth/         # Auth-related components
│   └── {feature}/    # Feature-specific components
├── hooks/            # Custom React hooks
├── contexts/         # React contexts
├── lib/              # Utilities (supabase client, etc)
├── pages/            # Route components
└── types/            # TypeScript types
```

## Code rules

### Components
- One component per file
- Named exports (not default)
- Each folder has `index.ts` which re-exports all components

```typescript
// src/components/ui/index.ts
export { Button } from './Button'
export { Input } from './Input'
export { Card } from './Card'
```

### Hooks
- Prefix with `use`
- Return objects with named values
- Handle loading and error states

```typescript
export function useTodos() {
  const [todos, setTodos] = useState<Todo[]>([])
  const [loading, setLoading] = useState(true)
  const [error, setError] = useState<string | null>(null)

  // ...

  return { todos, loading, error, addTodo, updateTodo, deleteTodo }
}
```

### Supabase
- Client in `src/lib/supabase.ts`
- Types in `src/lib/database.types.ts`
- RLS policies for all data
- Use `user_id` for row-level access

### Styling
- Use Tailwind utility classes
- Define design tokens in `tailwind.config.js`
- Use CSS variables for themes

## Verification

After each epic, run:
```bash
npm run build          # No compile errors
npm test               # Unit tests pass
npx playwright test    # E2E tests pass
```

## E2E Tests (Playwright)

E2E tests should test **the whole user flow**, not just the page loading.

**Requirements for auth apps:**
- Test login flow (magic link or password)
- Retrieve magic link from Mailpit (`localhost:54324`) if needed
- Verify that user gets to the right page after login
- Test CRUD operations as logged in user

**Example of good E2E test:**
```typescript
test('user can login and create todo', async ({ page }) => {
  // 1. Go to login
  await page.goto('/login');

  // 2. Log in (adapt to your auth method)
  await page.fill('input[type="email"]', 'test@example.com');
  await page.click('button:has-text("Log in")');

  // 3. Verify redirect to app
  await expect(page).toHaveURL('/');

  // 4. Create a todo
  await page.fill('input[placeholder*="todo"]', 'My new todo');
  await page.click('button:has-text("Add")');

  // 5. Verify it was created
  await expect(page.locator('text=My new todo')).toBeVisible();
});
```

**IMPORTANT:** If E2E tests only test that the "page loads" - they are too superficial! Create tests that verify that the app actually works.

## Supabase Setup

Before auth development:
```bash
supabase start                    # Start local instance
supabase db reset                 # Run migrations
# Update .env with credentials from 'supabase status'
```

## Port exposure for testing

For external testing (browser outside VM):
```bash
# Dev server on all interfaces
npm run dev -- --host 0.0.0.0

# Supabase is already exposed on 0.0.0.0:54321
```

**IMPORTANT for E2E testing:**
- Playwright runs headless on VM
- Mailpit for magic links: `http://localhost:54324`
- API to fetch mail programmatically: `http://localhost:54324/api/v1/messages`

## Regression Testing

When making changes, ensure that existing functionality is not broken:

1. **Run all unit tests** - `npm test`
2. **Run E2E tests** - `npx playwright test`
3. **Manually test** - Open the app and verify basic flows

**Regression test checklist:**
- [ ] Login works (magic link or password)
- [ ] CRUD on main entity (e.g. todos)
- [ ] Logout works
- [ ] Error handling is displayed correctly
- [ ] Responsive design (mobile/desktop)

## Common Mistakes

1. **Forgotten export** - New component must be added to index.ts
2. **Missing prop** - Check that all required props are sent
3. **Supabase not started** - Gives "Failed to fetch" in browser
4. **RLS blocking** - Check policies if data is not displayed
5. **Wrong redirect URL** - Check `supabase/config.toml` site_url
