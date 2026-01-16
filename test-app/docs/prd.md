# PRD: Aussie Atlas (Australian Shepherd Guide)

## Summary
A lightweight informational React application about Australian Shepherds that helps prospective owners and fans learn about:

- Breed characteristics and temperament
- Care requirements (exercise, grooming, training)
- Common health considerations
- Practical tips and checklists

The app should feel like a real product (navigation, consistent layout, interactive feature) and include meaningful E2E tests.

## Target users
- Prospective owners deciding if an Aussie fits their lifestyle
- Current owners wanting quick care references
- Breed enthusiasts

## Functional requirements

### FR1: Core informational pages
- Provide pages for: Overview, Characteristics, Care, Health, About/Resources
- Content should be written and structured (not lorem ipsum)

### FR2: Data-driven content
- Store breed facts, care tips, and health notes in a typed data module
- Render UI based on this data (cards/lists)

### FR3: Interactive quiz
- A short quiz: “Is an Aussie right for me?”
- Shows a scored result + recommendations
- Result should be deterministic based on answers

### FR4: Favorites
- Users can favorite care tips
- Favorites persist via localStorage

### FR5: Search/filter
- Users can filter care tips by category (Exercise, Grooming, Training, Nutrition)
- Optional: free-text search over tips

## Non-functional requirements
- Fast load (no backend)
- Accessible UI (labels, focus states)
- Responsive (mobile + desktop)
- No external paid APIs

## UX / Design
- Simple, friendly layout
- Hero section on home with quick facts
- Consistent navigation
- Use Tailwind tokens and spacing scale

## Testing (E2E)
Playwright tests must cover real user flows:

- Navigation between pages
- Completing the quiz and seeing a result
- Favoriting/unfavoriting a tip and verifying persistence
- Filtering tips and verifying results

## Out of scope
- User accounts
- Backend/database
- Image upload

## Open questions
- Do we want a dark mode toggle? (Optional)
